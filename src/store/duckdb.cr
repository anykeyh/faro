require "duckdb"
require "db"

module Faro::Store
  class DuckDB
    getter path : String
    getter connection : DB::Connection

    BUCKET_SIZE = 1.minute

    def initialize(@path : String)
      # Use a single dedicated connection via DB.connect (not DB.open which
      # uses a pool).  This is essential for in-memory DuckDB because each
      # DuckDB connection creates its own separate in-memory database.
      uri = @path == ":memory:" ? ::DuckDB::IN_MEMORY : "duckdb://#{@path}"
      @connection = DB.connect(uri)
    end

    def setup_schema
      @connection.exec(<<-SQL)
        CREATE TABLE IF NOT EXISTS sensors (
          name        VARCHAR     NOT NULL,
          metric      VARCHAR     NOT NULL,
          value       DOUBLE,
          avg         DOUBLE,
          k           INTEGER     NOT NULL DEFAULT 1,
          dev         DOUBLE      NOT NULL DEFAULT 0.0,
          min         DOUBLE,
          max         DOUBLE,
          from_ts     TIMESTAMP   NOT NULL,
          to_ts       TIMESTAMP   NOT NULL,
          resolved_at TIMESTAMP   NOT NULL,
          PRIMARY KEY (name, metric, from_ts)
        )
      SQL
      @connection.exec(<<-SQL)
        CREATE INDEX IF NOT EXISTS idx_sensors_name_from
          ON sensors (name, from_ts)
      SQL

      @connection.exec(<<-SQL)
        CREATE TABLE IF NOT EXISTS latch_events (
          id           INTEGER,
          name         VARCHAR     NOT NULL,
          latch        VARCHAR     NOT NULL,
          metric       VARCHAR     NOT NULL,
          value        DOUBLE      NOT NULL,
          from_ts      TIMESTAMP   NOT NULL,
          to_ts        TIMESTAMP,
          acknowledged BOOLEAN     DEFAULT FALSE
        )
      SQL
      @connection.exec(<<-SQL)
        CREATE INDEX IF NOT EXISTS idx_latch_events_name
          ON latch_events (name, latch)
      SQL
    end

    def write(adapter_name : String, data : Hash(String, Float64), timestamp : Time)
      return if data.empty?
      bucket_start = bucket_floor(timestamp)
      bucket_end   = bucket_start + BUCKET_SIZE
      data.each do |metric, value|
        existing = read_existing(adapter_name, metric, bucket_start)
        if existing.nil?
          @connection.exec(
            "INSERT INTO sensors (name, metric, value, avg, k, dev, min, max, from_ts, to_ts, resolved_at)
             VALUES (?, ?, ?, ?, 1, 0.0, ?, ?, ?, ?, ?)",
            adapter_name, metric, value, value, value, value,
            bucket_start, bucket_end, timestamp
          )
        else
          k_old, avg_old, dev_old, min_old, max_old = existing[:k], existing[:avg], existing[:dev], existing[:min], existing[:max]
          k_new   = k_old + 1
          avg_new = avg_old + (value - avg_old) / k_new
          dev_new = dev_old + (value - avg_old) * (value - avg_new)
          min_new = Math.min(min_old, value)
          max_new = Math.max(max_old, value)
          midpoint = bucket_start + (BUCKET_SIZE / 2)
          @connection.exec(
            "UPDATE sensors SET value = ?, avg = ?, k = ?, dev = ?, min = ?, max = ?, to_ts = ?, resolved_at = ?
             WHERE name = ? AND metric = ? AND from_ts = ?",
            value, avg_new, k_new, dev_new, min_new, max_new, bucket_end, midpoint,
            adapter_name, metric, bucket_start
          )
        end
      end
    end

    def query(adapter_name : String, since : Time, finish : Time) : Array(NamedTuple(
      metric: String, value: Float64?, avg: Float64?, k: Int32, dev: Float64,
      min: Float64?, max: Float64?, from_ts: Time, to_ts: Time, resolved_at: Time
    ))
      rows = [] of NamedTuple(
        metric: String, value: Float64?, avg: Float64?, k: Int32, dev: Float64,
        min: Float64?, max: Float64?, from_ts: Time, to_ts: Time, resolved_at: Time
      )
      @connection.query(<<-SQL, adapter_name, since, finish) do |rs|
          SELECT metric, value, avg, k, dev, min, max, from_ts, to_ts, resolved_at
          FROM sensors
          WHERE name = ? AND from_ts >= ? AND from_ts < ?
          ORDER BY from_ts ASC
        SQL
        rs.each do
          rows << {metric: rs.read(String), value: rs.read(Float64?), avg: rs.read(Float64?),
                   k: rs.read(Int32), dev: rs.read(Float64), min: rs.read(Float64?),
                   max: rs.read(Float64?), from_ts: rs.read(Time), to_ts: rs.read(Time),
                   resolved_at: rs.read(Time)}
        end
      end
      rows
    end

    def list_names : Array(NamedTuple(name: String, metric: String))
      rows = [] of NamedTuple(name: String, metric: String)
      @connection.query("SELECT DISTINCT name, metric FROM sensors ORDER BY name, metric") do |rs|
        rs.each { rows << {name: rs.read(String), metric: rs.read(String)} }
      end
      rows
    end

    # ── Threshold / Latch methods ────────────────────────────────────────────

    def latest_value(adapter_name : String, metric : String) : Float64?
      result = nil
      @connection.query(
        "SELECT value FROM sensors WHERE name = ? AND metric = ? ORDER BY from_ts DESC LIMIT 1",
        adapter_name, metric
      ) do |rs|
        rs.each { result = rs.read(Float64?) }
      end
      result
    end

    def latch_open?(threshold_name : String, latch_name : String) : Bool
      count = 0_i64
      @connection.query(
        "SELECT COUNT(*) FROM latch_events WHERE name = ? AND latch = ? AND to_ts IS NULL",
        threshold_name, latch_name
      ) do |rs|
        rs.each { count = rs.read(Int64) }
      end
      count > 0
    end

    def open_latch(threshold_name : String, latch_name : String, metric : String, value : Float64, now : Time)
      @connection.exec(
        "INSERT INTO latch_events (name, latch, metric, value, from_ts) VALUES (?, ?, ?, ?, ?)",
        threshold_name, latch_name, metric, value, now
      )
    end

    def close_latch(threshold_name : String, latch_name : String, value : Float64, now : Time)
      @connection.exec(
        "UPDATE latch_events SET to_ts = ?, value = ? WHERE name = ? AND latch = ? AND to_ts IS NULL",
        now, value, threshold_name, latch_name
      )
    end

    def open_latches : Array(NamedTuple(name: String, latch: String, metric: String, value: Float64, from_ts: Time))
      rows = [] of NamedTuple(name: String, latch: String, metric: String, value: Float64, from_ts: Time)
      @connection.query(<<-SQL) do |rs|
          SELECT name, latch, metric, value, from_ts
          FROM latch_events
          WHERE to_ts IS NULL
          ORDER BY name, latch
        SQL
        rs.each do
          rows << {name: rs.read(String), latch: rs.read(String), metric: rs.read(String),
                   value: rs.read(Float64), from_ts: rs.read(Time)}
        end
      end
      rows
    end

    def clear_data
      @connection.exec("DELETE FROM sensors")
      @connection.exec("DELETE FROM latch_events")
    end

    def close
      @connection.close
    end

    private def read_existing(name, metric, bucket_start)
      existing = nil
      @connection.query("SELECT k, avg, dev, min, max FROM sensors WHERE name = ? AND metric = ? AND from_ts = ?",
                         name, metric, bucket_start) do |rs|
        rs.each { existing = {k: rs.read(Int32), avg: rs.read(Float64), dev: rs.read(Float64), min: rs.read(Float64), max: rs.read(Float64)} }
      end
      existing
    end

    private def bucket_floor(ts : Time) : Time
      span = ts - Time::UNIX_EPOCH
      floored = span - (span.total_seconds % BUCKET_SIZE.total_seconds).seconds
      Time::UNIX_EPOCH + floored
    end
  end
end
