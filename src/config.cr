require "yaml"
require "./time_parser"

struct Faro::Config
  include YAML::Serializable

  property db : String = ":memory:"
  property probes : Array(String)?  # nil = all system probes with 5s interval
  property adapters : Array(AdapterConfig) = [] of AdapterConfig
  property thresholds : Array(ThresholdConfig) = [] of ThresholdConfig
  property notifications : Array(NotificationConfig) = [] of NotificationConfig
  property server : ServerConfig = ServerConfig.from_yaml("host: 0.0.0.0\nport: 3000\n")

  struct AdapterConfig
    include YAML::Serializable

    property name : String
    property run : String?
    property args : Array(String)?
    property env : Hash(String, String)?
    property via : ViaConfig?
    @[YAML::Field(converter: Faro::TimeStringConverter)]
    property collect_interval : Float64?  # seconds, supports "10s", "5m", "1h"
    @[YAML::Field(converter: Faro::TimeStringConverter)]
    property timeout : Float64?           # seconds, optional

    # Convenience constructor for auto-generated system probes.
    def initialize(@name : String, @run : String?, @collect_interval : Float64?,
                   @args : Array(String)? = nil, @env : Hash(String, String)? = nil,
                   @via : ViaConfig? = nil, @timeout : Float64? = nil)
    end

    # Returns collect_interval with a minimum of 1.0
    def effective_interval : Float64
      Math.max(collect_interval || 10.0, 1.0)
    end
  end

  struct ServerConfig
    include YAML::Serializable

    property host : String = "0.0.0.0"
    property port : Int32 = 3000
  end

  struct ViaConfig
    include YAML::Serializable

    property type : String
    property container : String?
    property host : String?
    property namespace : String?
  end

  struct ThresholdConfig
    include YAML::Serializable

    property name : String
    property metric : String
    property latches : Array(LatchConfig)

    def above?
      latches.all? { |l| l.set > l.release }
    end
  end

  struct LatchConfig
    include YAML::Serializable

    property name : String
    @[YAML::Field(converter: Faro::NumberStringConverter)]
    property set : Float64
    @[YAML::Field(converter: Faro::NumberStringConverter)]
    property release : Float64
    @[YAML::Field(converter: Faro::TimeStringConverter)]
    property sustain : Float64?  # seconds, optional

    def validate!
      if set == release
        raise "latch '#{name}': set and release must differ (got #{set} == #{release})"
      end
    end
  end

  struct NotificationConfig
    include YAML::Serializable

    property on : String
    property script : String
  end

  # All system probes with their recommended 5s interval.
  SYSTEM_PROBES = {
    "cpu"       => "$cpu",
    "memory"    => "$memory",
    "disk"      => "$disk",
    "load"      => "$load",
    "network"   => "$network",
    "swap"      => "$swap",
    "processes" => "$processes",
    "system"    => "$system",
    "thermal"   => "$thermal",
  }

  SYSTEM_PROBE_INTERVAL = 5.0

  # Returns the effective list of adapters to run.
  # Merges default system probes with user-defined overrides.
  def effective_adapters : Array(AdapterConfig)
    # Determine which system probes to auto-generate
    selected_probes = if (p = probes).nil?
                        # Not set → all system probes
                        SYSTEM_PROBES.keys
                      elsif p.empty?
                        # Explicitly empty → no system probes at all
                        [] of String
                      else
                        # User-specified list of $name references
                        p.map { |ref| ref.starts_with?('$') ? ref.lchop('$') : ref }
                      end

    # Build auto-generated system adapters (5s interval)
    probe_adapters = selected_probes.map do |probe_name|
      run_ref = SYSTEM_PROBES[probe_name]? || "$#{probe_name}"
      AdapterConfig.new(
        name: probe_name,
        run: run_ref,
        collect_interval: SYSTEM_PROBE_INTERVAL,
      )
    end

    # Merge with explicit adapters — explicit ones override by name
    explicit = adapters.index_by(&.name)
    probe_adapters.map do |pa|
      explicit[pa.name]? || pa
    end + adapters.reject { |a| probe_adapters.any? { |pa| pa.name == a.name } }
  end

  def self.load(path : String) : self
    from_yaml(File.read(path)).tap(&.validate!)
  end

  def validate!
    thresholds.each do |t|
      t.latches.each(&.validate!)
    end
  end
end

# Helper: index an array of structs by a key proc
module Enumerable
  def index_by(&block : T -> K) : Hash(K, T) forall T, K
    h = {} of K => T
    each { |e| h[yield e] = e }
    h
  end
end

# YAML converter that accepts a number (int or float) or a numeric string.
module Faro::NumberStringConverter
  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Float64
    if node.is_a?(YAML::Nodes::Scalar)
      node.value.to_f64
    else
      raise "expected a scalar, got #{node.class}"
    end
  end

  def self.to_yaml(value : Float64, builder : YAML::Nodes::Builder)
    value.to_yaml(builder)
  end
end

# YAML converter that accepts either a number (seconds) or a time string ("5m", "1h").
module Faro::TimeStringConverter
  def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Float64?
    if node.is_a?(YAML::Nodes::Scalar)
      raw = node.value
      # Try as bare number first
      if raw =~ /^\d+(?:\.\d+)?$/
        raw.to_f64
      elsif raw.empty?
        nil
      else
        TimeParser.parse(raw).total_seconds
      end
    else
      nil
    end
  end

  def self.to_yaml(value : Float64?, builder : YAML::Nodes::Builder)
    value.to_yaml(builder)
  end
end
