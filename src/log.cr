require "log"

# Faro's logging facade.
#
# Configuration is stored in a class variable so it can be set once at startup
# and used everywhere without passing a config object around.
module Faro
  module Log
    # The backend log source.
    SOURCE = ::Log.for("faro")

    # Configure the log level for both Faro and Kemal.
    def self.setup(level : String)
      log_level = parse_level(level)
      ::Log.setup("faro", :trace, ::Log::IOBackend.new(formatter: formatter))
      ::Log.setup("kemal", log_level, ::Log::IOBackend.new(formatter: kemal_formatter))
    end

    def self.debug(msg : String)
      SOURCE.debug { msg }
    end

    def self.info(msg : String)
      SOURCE.info { msg }
    end

    def self.warn(msg : String)
      SOURCE.warn { msg }
    end

    def self.error(msg : String)
      SOURCE.error { msg }
    end

    def self.trace(msg : String)
      SOURCE.trace { msg }
    end

    private def self.parse_level(level : String) : ::Log::Severity
      case level.downcase
      when "trace"  then ::Log::Severity::Trace
      when "debug"  then ::Log::Severity::Debug
      when "info"   then ::Log::Severity::Info
      when "warn"   then ::Log::Severity::Warn
      when "error"  then ::Log::Severity::Error
      when "fatal"  then ::Log::Severity::Fatal
      else               ::Log::Severity::Warn
      end
    end

    private def self.formatter : ::Log::Formatter
      ::Log::Formatter.new do |entry, io|
        io << entry.severity.label
        io << " ["
        io << entry.timestamp.to_rfc3339
        io << "] "
        io << entry.message
      end
    end

    private def self.kemal_formatter : ::Log::Formatter
      ::Log::Formatter.new do |entry, io|
        io << entry.severity.label
        io << " ["
        io << entry.timestamp.to_rfc3339
        io << "] [kemal] "
        io << entry.message
      end
    end
  end
end
