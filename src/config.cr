require "yaml"

struct Faro::Config
  include YAML::Serializable

  property db : String = ":memory:"
  property adapters : Array(AdapterConfig) = [] of AdapterConfig
  property thresholds : Array(ThresholdConfig) = [] of ThresholdConfig
  property server : ServerConfig = ServerConfig.from_yaml("host: 0.0.0.0\nport: 3000\n")

  struct AdapterConfig
    include YAML::Serializable

    property name : String
    property run : String?
    property args : Array(String)?
    property env : Hash(String, String)?
    property via : ViaConfig?
    property collect_interval : Float64?  # seconds, min 1.0
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
  end

  struct LatchConfig
    include YAML::Serializable

    property name : String
    property set : Float64
    property release : Float64
  end

  def self.load(path : String) : self
    File.open(path) { |io| self.from_yaml(io) }
  end
end
