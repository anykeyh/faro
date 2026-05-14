require "kemal"
require "json"
require "../store/bucketing"

module Faro::API
  class Server
    @store : Faro::Store::Bucketing
    @frontend_path : String

    def initialize(@store : Faro::Store::Bucketing, host : String = "0.0.0.0", port : Int32 = 3000)
      @frontend_path = File.join(__DIR__, "../../frontend")
      Kemal.config.port = port
      Kemal.config.host_binding = host
      Kemal.config.env = "production"
    end

    def start
      get "/" do |env|
        send_file env, File.join(@frontend_path, "index.html")
      end

      get "/styles.css" do |env|
        send_file env, File.join(@frontend_path, "styles.css")
      end

      get "/app.js" do |env|
        send_file env, File.join(@frontend_path, "app.js")
      end

      get "/mithril.js" do |env|
        send_file env, File.join(@frontend_path, "mithril.js")
      end

      get "/api.js" do |env|
        send_file env, File.join(@frontend_path, "api.js")
      end

      get "/store.js" do |env|
        send_file env, File.join(@frontend_path, "store.js")
      end

      get "/components/header.js" do |env|
        send_file env, File.join(@frontend_path, "components", "header.js")
      end

      get "/components/indicator_card.js" do |env|
        send_file env, File.join(@frontend_path, "components", "indicator_card.js")
      end

      get "/components/graph_card.js" do |env|
        send_file env, File.join(@frontend_path, "components", "graph_card.js")
      end

      get "/components/add_card.js" do |env|
        send_file env, File.join(@frontend_path, "components", "add_card.js")
      end

      get "/components/dashboard.js" do |env|
        send_file env, File.join(@frontend_path, "components", "dashboard.js")
      end

      get "/health" do |env|
        env.response.content_type = "application/json"
        {"status" => "ok", "timestamp" => Time.utc.to_rfc3339}.to_json
      end

      get "/api/sensors" do |env|
        env.response.content_type = "application/json"
        @store.list_names.to_json
      end

      get "/api/sensors/:name" do |env|
        env.response.content_type = "application/json"

        name   = env.params.url["name"]
        since  = parse_time(env.params.query["since"]?) || (Time.utc - 1.hour)
        finish = parse_time(env.params.query["until"]?) || Time.utc

        rows = @store.query(name, since, finish)
        grouped = {} of String => Array(NamedTuple(
          value: Float64?, avg: Float64?, k: Int32, dev: Float64,
          min: Float64?, max: Float64?, from_ts: String, to_ts: String, resolved_at: String
        ))

        rows.each do |row|
          key = row[:metric]
          grouped[key] ||= [] of NamedTuple(
            value: Float64?, avg: Float64?, k: Int32, dev: Float64,
            min: Float64?, max: Float64?, from_ts: String, to_ts: String, resolved_at: String
          )
          grouped[key] << {
            value:       row[:value],
            avg:         row[:avg],
            k:           row[:k],
            dev:         row[:dev],
            min:         row[:min],
            max:         row[:max],
            from_ts:     row[:from_ts].to_rfc3339,
            to_ts:       row[:to_ts].to_rfc3339,
            resolved_at: row[:resolved_at].to_rfc3339,
          }
        end

        {"name" => name, "since" => since.to_rfc3339, "until" => finish.to_rfc3339, "series" => grouped}.to_json
      end

      # Prometheus /metrics endpoint — exposes all latest values with labels.
      get "/metrics" do |env|
        env.response.content_type = "text/plain; version=0.0.4"

        # Build a set of (name, metric) → latest value
        metrics = {} of String => Array(NamedTuple(metric: String, value: Float64))

        @store.list_names.each do |entry|
          name = entry[:name]
          metric = entry[:metric]
          value = @store.latest_value(name, metric)
          next if value.nil?

          metrics[name] ||= [] of NamedTuple(metric: String, value: Float64)
          metrics[name] << {metric: metric, value: value.not_nil!}
        end

        String.build do |io|
          io << "# HELP faro_adapter_metric Latest sensor reading.\n"
          io << "# TYPE faro_adapter_metric gauge\n"

          metrics.each do |adapter, points|
            points.each do |p|
              io << "faro_adapter_metric{adapter=\""
              io << adapter
              io << "\",metric=\""
              io << p[:metric]
              io << "\"} "
              io << p[:value].to_s
              io << "\n"
            end
          end
        end
      end

      Kemal.run
    end

    private def parse_time(str : String?) : Time?
      return nil unless str
      Time.parse_rfc3339(str)
    rescue
      nil
    end
  end
end
