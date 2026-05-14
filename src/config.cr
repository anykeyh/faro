require "yaml"
require "./time_parser"

struct Faro::Config
  include YAML::Serializable

  property db : String = ":memory:"
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

  def self.load(path : String) : self
    from_yaml(File.read(path)).tap(&.validate!)
  end

  def validate!
    thresholds.each do |t|
      t.latches.each(&.validate!)
    end
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
