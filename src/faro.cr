require "./config"
require "./probes"
require "./runners/container"
require "./store/db"
require "./store/bucketing"
require "./api/server"
require "./log"

module Faro
  DEFAULT_INTERVAL = 10.0

  def self.run(config : Config)
    # Setup logging
    Faro::Log.setup(config.log.level, config.log.output, config.log.error)

    db = Store::Db.new(config.db)
    db.setup_schema
    store = Store::Bucketing.new(db, config.storage)

    runner = RunnerContainer.new

    # Temp files for embedded probes — cleaned up on exit.
    temp_files = [] of String

    # ── Log startup info ────────────────────────────────────────────

    Faro::Log.info "Faro v#{version} starting"
    Faro::Log.info "Database: #{config.db}"
    Faro::Log.info "Log level: #{config.log.level}"
    Faro::Log.info "Log output: #{config.log.output}"
    Faro::Log.info "Log error: #{config.log.error}"

    config.effective_adapters.each do |adapter|
      spawn_adapter(adapter, runner, store, temp_files, config.thresholds)
    end

    # Meta healthy probe — periodically checks that all adapters are alive
    spawn(name: "meta:healthy") do
      loop do
        sleep 10.seconds
        begin
          all_alive = config.effective_adapters.all? do |a|
            v = store.latest_value(a.name, "_alive")
            v && v > 0.5
          end
          store.write("meta", {"healthy" => all_alive ? 1.0 : 0.0}, Time.utc)
          if !all_alive
            Faro::Log.debug "meta: one or more adapters are down"
          end
        rescue ex
          Faro::Log.error "meta healthy probe: #{ex.message}"
        end
      end
    end

    # ── Log thresholds info ─────────────────────────────────────────

    config.thresholds.each do |t|
      t.latches.each do |l|
        dir = l.set > l.release ? "above" : "below"
        Faro::Log.info "Threshold: #{t.name}.#{l.name} (#{dir}, set=#{l.set}, release=#{l.release}#{l.sustain ? ", sustain=#{l.sustain}s" : ""})"
      end
    end

    # Clean up temp files on exit.
    at_exit do
      temp_files.each { |p| File.delete(p) rescue nil }
    end

    server_config = config.server
    API::Server.new(store, config.thresholds, server_config).start
  end

  private def self.spawn_adapter(adapter, runner, store, temp_files, thresholds)
    Faro::Log.info "Adapter: #{adapter.name} (run: #{adapter.run}, interval: #{adapter.effective_interval}s)"

    sleep_span = adapter.effective_interval.seconds

    raw_run = adapter.run
    if raw_run.nil?
      Faro::Log.warn "Adapter '#{adapter.name}' has no 'run' directive, skipping"
      return
    end

    script_path = if raw_run.starts_with?('$')
                    name = raw_run.lchop('$')
                    content = EmbeddedProbes.resolve(raw_run)
                    if content.nil?
                      Faro::Log.warn "Unknown probe '#{name}' for adapter '#{adapter.name}', skipping"
                      return
                    end
                    tmp = File.tempfile("faro_#{name}", ".sh") do |f|
                      f.print(content)
                    end
                    File.chmod(tmp.path, 0o755)
                    temp_files << tmp.path
                    tmp.path
                  else
                    raw_run
                  end

    spawn(name: "adapter:#{adapter.name}") do
      loop do
        begin
          result = runner.run(script_path, args: adapter.args, env: adapter.env, via: adapter.via)
          if result.success?
            data = Hash(String, Float64).from_json(result.stdout)
            data["_alive"] = 1.0
            store.write(adapter.name, data, Time.utc)
            Faro::Log.trace "[#{adapter.name}] ok (#{data.size} metrics)"
          else
            Faro::Log.warn "[#{adapter.name}] exit #{result.exit_code}: #{result.stderr.strip}"
            data = {"_alive" => 0.0}
            store.write(adapter.name, data, Time.utc)
          end

          # Evaluate thresholds for this adapter
          now = Time.utc
          thresholds.each do |t|
            # t.metric is "adapter_name.metric_name"
            parts = t.metric.split(".", 2)
            next unless parts.size == 2 && parts[0] == adapter.name
            metric_name = parts[1]
            value = data[metric_name]?
            next if value.nil?
            t.latches.each do |l|
              store.evaluate_latch(t.name, metric_name, l.name,
                set: l.set, release: l.release, value: value, sustain: l.sustain, now: now)
            end
          end
        rescue ex
          Faro::Log.warn "ERROR in adapter '#{adapter.name}': #{ex.message}"
          store.write(adapter.name, {"_alive" => 0.0}, Time.utc)
        end
        sleep sleep_span
      end
    end
  end

  def self.version : String
    {{ read_file("shard.yml").split("\n").find(&.starts_with?("version:")).split(": \"")[1].split("\"")[0].strip || "unknown" }}
  end
end
