require "log"

module Faro
  module Log
    SOURCE = ::Log.for("faro")

    # Configure logging.
    # - output: receives trace, debug, info (info-level and below)
    # - error: receives warn, error, fatal (warn-level and above)
    def self.setup(level : String, output : String = "/dev/stdout", error : String = "/dev/stderr")
      log_level = parse_level(level)

      out_io = output == "/dev/stdout" ? STDOUT : File.open(output, "a")
      out_io.sync = true
      err_io = error == "/dev/stderr" ? STDERR : File.open(error, "a")
      err_io.sync = true

      # Truncate from trace up to info → stdout
      stdout_backend = MaxLevelBackend.new(
        ::Log::IOBackend.new(io: out_io, formatter: formatter, dispatcher: ::Log::DispatchMode::Sync),
        ::Log::Severity::Info
      )
      # warn and above → stderr (no cap)
      stderr_backend = ::Log::IOBackend.new(io: err_io, formatter: formatter, dispatcher: ::Log::DispatchMode::Sync)

      broadcast = ::Log::BroadcastBackend.new
      broadcast.append(stdout_backend, ::Log::Severity::Trace)
      broadcast.append(stderr_backend, ::Log::Severity::Warn)

      ::Log.setup do |c|
        c.bind "*",     :warn,  broadcast  # fallback
        c.bind "faro",  log_level, broadcast
        c.bind "kemal", log_level, broadcast
      end
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
        if entry.source == "kemal"
          io << "[kemal] "
        end
        io << entry.message
      end
    end
  end

  # Wraps a backend and caps it at a maximum severity.
  # Messages above the cap are silently dropped.
  class MaxLevelBackend < ::Log::Backend
    def initialize(@backend : ::Log::Backend, @max : ::Log::Severity)
      super(::Log::DirectDispatcher)
    end

    def write(entry : ::Log::Entry)
      @backend.write(entry) if entry.severity <= @max
    end
  end
end
