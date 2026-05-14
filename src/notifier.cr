require "./log"

# Runs notification scripts when latches open or close.
# The script receives latch details as environment variables:
#   FARO_EVENT        = "open" | "close"
#   FARO_NAME         = threshold name
#   FARO_LATCH        = latch name
#   FARO_METRIC       = metric name
#   FARO_VALUE        = trigger value
#   FARO_TIMESTAMP    = ISO 8601 timestamp

module Faro
  class Notifier
    @scripts : Array(NamedTuple(on: String, script: String))

    def initialize(notifications : Array(Faro::Config::NotificationConfig))
      @scripts = notifications.map { |n| {on: n.on, script: n.script} }
    end

    def notify(event : String, name : String, latch : String, metric : String, value : Float64, ts : Time)
      @scripts.each do |s|
        # Match: "probe.cpu" matches on name, "cpu-high.critical" matches name.latch
        parts = s[:on].split(".")
        case parts.size
        when 1
          next unless parts[0] == name
        when 2
          next unless parts[0] == name && parts[1] == latch
        else
          next
        end

        env = {
          "FARO_EVENT"     => event,
          "FARO_NAME"      => name,
          "FARO_LATCH"     => latch,
          "FARO_METRIC"    => metric,
          "FARO_VALUE"     => value.to_s,
          "FARO_TIMESTAMP" => ts.to_rfc3339,
        }

        spawn do
          begin
            Process.run(s[:script], env: env,
              output: Process::Redirect::Close,
              error: Process::Redirect::Close)
          rescue ex
            Faro::Log.error "Notification script '#{s[:script]}' failed: #{ex.message}"
          end
        end
      end
    end
  end
end
