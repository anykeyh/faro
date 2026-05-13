require "./config"
require "./runners/container"
require "./store/duckdb"
require "./api/server"

module Faro
  DEFAULT_INTERVAL = 10.0

  def self.run(config : Config)
    store = Store::DuckDB.new(config.db)
    store.setup_schema

    runner = RunnerContainer.new

    config.adapters.each do |adapter|
      interval = adapter.collect_interval || DEFAULT_INTERVAL
      interval = Math.max(interval, 1.0)
      sleep_span = interval.seconds

      spawn(name: "adapter:#{adapter.name}") do
        loop do
          begin
            if (script = adapter.run).nil?
              STDERR.puts "Unknown adapter: #{adapter.name}"
              sleep sleep_span
              next
            end

            result = runner.run(script, args: adapter.args, env: adapter.env, via: adapter.via)
            if result.success?
              data = Hash(String, Float64).from_json(result.stdout)
              store.write(adapter.name, data, Time.utc)
            else
              STDERR.puts "[#{adapter.name}] exit #{result.exit_code}: #{result.stderr}"
            end
          rescue ex
            STDERR.puts "ERROR in adapter '#{adapter.name}': #{ex.message}"
          end
          sleep sleep_span
        end
      end
    end

    server_config = config.server
    API::Server.new(store, host: server_config.host, port: server_config.port).start
  end
end
