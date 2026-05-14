require "./config"
require "./probes"
require "./runners/container"
require "./store/db"
require "./store/bucketing"
require "./api/server"

module Faro
  DEFAULT_INTERVAL = 10.0

  def self.run(config : Config)
    db = Store::Db.new(config.db)
    db.setup_schema
    store = Store::Bucketing.new(db)

    runner = RunnerContainer.new

    # Temp files for embedded probes — cleaned up on exit.
    temp_files = [] of String

    config.effective_adapters.each do |adapter|
      sleep_span = adapter.effective_interval.seconds

      raw_run = adapter.run
      if raw_run.nil?
        STDERR.puts "Adapter '#{adapter.name}' has no 'run' directive"
        next
      end

      # Resolve $name → embedded script or filesystem path.
      script_path = if raw_run.starts_with?('$')
                      name = raw_run.lchop('$')
                      content = EmbeddedProbes.resolve(raw_run)
                      if content.nil?
                        STDERR.puts "Unknown probe '#{name}' for adapter '#{adapter.name}'"
                        next
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
            else
              STDERR.puts "[#{adapter.name}] exit #{result.exit_code}: #{result.stderr}"
              store.write(adapter.name, {"_alive" => 0.0}, Time.utc)
            end
          rescue ex
            STDERR.puts "ERROR in adapter '#{adapter.name}': #{ex.message}"
            store.write(adapter.name, {"_alive" => 0.0}, Time.utc)
          end
          sleep sleep_span
        end
      end
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
        rescue ex
          STDERR.puts "ERROR in meta healthy probe: #{ex.message}"
        end
      end
    end

    # Clean up temp files on exit.
    at_exit do
      temp_files.each { |p| File.delete(p) rescue nil }
    end

    server_config = config.server
    API::Server.new(store, config.thresholds, host: server_config.host, port: server_config.port).start
  end
end
