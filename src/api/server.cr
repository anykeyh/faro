require "kemal"
require "json"
require "../store/bucketing"
require "./embedded_frontend"
require "./basic_auth_handler"
require "../config"

module Faro::API
  class Server
    @store : Faro::Store::Bucketing
    @thresholds : Array(Faro::Config::ThresholdConfig)
    @frontend_path : String

    def initialize(@store : Faro::Store::Bucketing, @thresholds : Array(Faro::Config::ThresholdConfig), server_config : Faro::Config::ServerConfig)
      @frontend_path = File.join(__DIR__, "../../frontend")
      Kemal.config.port = server_config.port
      Kemal.config.host_binding = server_config.host
      Kemal.config.env = "production"

      # Optional HTTP Basic Auth
      if auth = server_config.basic_auth
        Kemal.config.add_handler(
          Faro::API::BasicAuthHandler.new(auth.username, auth.password)
        )
      end
    end

    def start
      # ── Static files (embedded when --release, disk otherwise) ──

      static_routes = [
        "/",
        "/styles.css",
        "/app.js",
        "/mithril.js",
        "/api.js",
        "/store.js",
        "/components/header.js",
        "/components/indicator_card.js",
        "/components/graph_card.js",
        "/components/latch_card.js",
        "/components/add_card.js",
        "/components/dashboard.js",
      ]

      static_routes.each do |route|
        get route do |env|
          request_path = env.request.path

          # Try embedded frontend first (available in --release builds)
          lookup = request_path == "/" ? "/index.html" : request_path
          if (content = EmbeddedFrontend.get(lookup))
            content_type = case request_path
                           when /\.html?$/ then "text/html; charset=utf-8"
                           when /\.css$/   then "text/css; charset=utf-8"
                           when /\.js$/    then "application/javascript; charset=utf-8"
                           else                 "application/octet-stream"
                           end
            env.response.content_type = content_type
            content
          else
            # Fallback: serve from disk (dev mode)
            relative = request_path == "/" ? "index.html" : request_path.lchop('/')
            send_file env, File.join(@frontend_path, relative)
          end
        end
      end

      # ── API endpoints ───────────────────────────────────────────

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

        name = env.params.url["name"]
        since = parse_time(env.params.query["since"]?) || (Time.utc - 1.hour)
        finish = parse_time(env.params.query["until"]?) || Time.utc

        rows = @store.query(name, since, finish)

        # Build columnar format: { fields: [...], values: [[...], ...] }
        # fields = [metric, value, avg, k, dev, min, max, from_ts, to_ts, resolved_at]
        # Each value row is an array matching the field order.
        fields = ["metric", "value", "avg", "k", "dev", "min", "max", "from_ts", "to_ts", "resolved_at"]
        values = rows.map do |row|
          [
            row[:metric],
            row[:value],
            row[:avg],
            row[:k],
            row[:dev],
            row[:min],
            row[:max],
            row[:from_ts].to_rfc3339,
            row[:to_ts].to_rfc3339,
            row[:resolved_at].to_rfc3339,
          ]
        end

        {"name" => name, "since" => since.to_rfc3339, "until" => finish.to_rfc3339, "fields" => fields, "values" => values}.to_json
      end

      # Lightweight endpoint: returns the latest value per metric (tiny payload)
      get "/api/sensors/:name/latest" do |env|
        env.response.content_type = "application/json"

        name = env.params.url["name"]

        entries = @store.list_names.select { |e| e[:name] == name }
        result = {} of String => Float64?

        entries.each do |entry|
          result[entry[:metric]] = @store.latest_value(name, entry[:metric])
        end

        {"name" => name, "values" => result}.to_json
      end

      # ── Latch endpoint ──────────────────────────────────────────

      get "/api/latches" do |env|
        env.response.content_type = "application/json"

        result = @thresholds.map do |t|
          latch_list = t.latches.map do |l|
            {
              name:    l.name,
              set:     l.set,
              release: l.release,
              sustain: l.sustain,
              open:    @store.latch_open?(t.name, l.name),
            }
          end

          {
            adapter: t.name,
            metric:  t.metric,
            latches: latch_list,
          }
        end

        result.to_json
      end

      # ── Prometheus /metrics ─────────────────────────────────────

      get "/metrics" do |env|
        env.response.content_type = "text/plain; version=0.0.4"

        metrics = {} of String => Array(NamedTuple(metric: String, value: Float64))

        @store.list_names.each do |entry|
          name = entry[:name]
          metric = entry[:metric]
          value = @store.latest_value(name, metric)
          next if value.nil?

          v = value.as(Float64)
          metrics[name] ||= [] of NamedTuple(metric: String, value: Float64)
          metrics[name] << {metric: metric, value: v}
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
