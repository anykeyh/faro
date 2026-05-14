require "./db"
require "../config"

module Faro::Store
  class Bucketing
    @db : AbstractBackend
    # Key: "name\0metric\0tier_index" → bucket number of latest write
    @last_seen : Hash(String, Int64)
    # Pending sustain timers: "name\0metric\0latch" → Time when value first crossed set
    @pending_open : Hash(String, Time)
    # Compaction tiers
    @tiers : Array(NamedTuple(size: Time::Span, age: Time::Span))
    # Purge age as a Time::Span
    @purge_age : Time::Span

    def initialize(@db : AbstractBackend, storage_config : Faro::Config::StorageConfig = Faro::Config::StorageConfig.new)
      @last_seen = {} of String => Int64
      @pending_open = {} of String => Time

      @tiers = storage_config.effective_tiers.map do |t|
        {size: t.effective_size.seconds, age: t.effective_age.seconds}
      end

      @purge_age = storage_config.effective_purge_after.seconds
    end

    # ── Write ────────────────────────────────────────────────────────────────

    def write(adapter_name : String, data : Hash(String, Float64), timestamp : Time)
      return if data.empty?

      data.each do |metric, value|
        @db.connection.exec(
          "INSERT INTO sensors (name, metric, value, avg, k, dev, min, max, from_ts, to_ts, resolved_at)
           VALUES (?, ?, ?, ?, 1, 0.0, ?, ?, ?, ?, ?)",
          adapter_name, metric, value, value, value, value,
          timestamp, timestamp, timestamp
        )
      end

      @tiers.each_with_index do |tier, idx|
        data.each do |metric, _|
          check_tier(adapter_name, metric, tier[:size], tier[:age], idx, timestamp)
        end
      end

      if timestamp.second == 0
        purge_old(timestamp)
      end
    end

    # ── Query ────────────────────────────────────────────────────────────────

    def query(adapter_name : String, since : Time, finish : Time) : Array(NamedTuple(
      metric: String, value: Float64?, avg: Float64?, k: Int32, dev: Float64,
      min: Float64?, max: Float64?, from_ts: Time, to_ts: Time, resolved_at: Time))
      @db.query(adapter_name, since, finish)
    end

    # ── Delegated methods ───────────────────────────────────

    def list_names
      @db.list_names
    end

    def latest_value(adapter_name : String, metric : String)
      @db.latest_value(adapter_name, metric)
    end

    def config_set(key : String, value : String) : Nil
      @db.config_set(key, value)
    end

    def config_get(key : String) : String?
      @db.config_get(key)
    end

    def latch_open?(threshold_name : String, latch_name : String) : Bool
      @db.latch_open?(threshold_name, latch_name)
    end

    def open_latch(threshold_name : String, latch_name : String, metric : String, value : Float64, now : Time)
      @db.open_latch(threshold_name, latch_name, metric, value, now)
    end

    def close_latch(threshold_name : String, latch_name : String, value : Float64, now : Time)
      @db.close_latch(threshold_name, latch_name, value, now)
    end

    def open_latches
      @db.open_latches
    end

    def clear_data
      @db.clear_data
    end

    def close
      @db.close
    end

    def setup_schema
      @db.setup_schema
    end

    # ── Threshold evaluation ────────────────────────────────────────

    def evaluate_latch(threshold_name : String, metric : String, latch_name : String,
                       set : Float64, release : Float64, value : Float64,
                       sustain : Float64?, now : Time)
      timer_key = "#{threshold_name}\0#{metric}\0#{latch_name}"

      if set > release
        if value >= set
          check_sustain_open(timer_key, threshold_name, latch_name, metric, value, sustain, now)
        elsif value <= release
          close_if_open(timer_key, threshold_name, latch_name, value, now)
        else
          @pending_open.delete(timer_key)
        end
      else
        if value <= set
          check_sustain_open(timer_key, threshold_name, latch_name, metric, value, sustain, now)
        elsif value >= release
          close_if_open(timer_key, threshold_name, latch_name, value, now)
        else
          @pending_open.delete(timer_key)
        end
      end
    end

    private def check_sustain_open(timer_key, threshold_name, latch_name, metric, value, sustain, now)
      if sustain && sustain > 0
        first_seen = @pending_open[timer_key]?
        if first_seen.nil?
          @pending_open[timer_key] = now
        elsif (now - first_seen).total_seconds >= sustain
          @pending_open.delete(timer_key)
          open_unless_open(threshold_name, latch_name, metric, value, now)
        end
      else
        open_unless_open(threshold_name, latch_name, metric, value, now)
      end
    end

    private def open_unless_open(threshold_name, latch_name, metric, value, now)
      unless latch_open?(threshold_name, latch_name)
        open_latch(threshold_name, latch_name, metric, value, now)
      end
    end

    private def close_if_open(timer_key, threshold_name, latch_name, value, now)
      @pending_open.delete(timer_key)
      if latch_open?(threshold_name, latch_name)
        close_latch(threshold_name, latch_name, value, now)
      end
    end

    # ── Private ──────────────────────────────────────────────────────────────

    private def check_tier(name : String, metric : String, size : Time::Span, age : Time::Span, tier_idx : Int32, now : Time)
      current_bucket = floor_to(now, size)
      key = "#{name}\0#{metric}\0#{tier_idx}"
      last_seen = @last_seen[key]?

      if last_seen.nil?
        @last_seen[key] = current_bucket
        return
      end

      return if current_bucket == last_seen

      age_in_buckets = (age.total_seconds / size.total_seconds).to_i64
      cutoff = current_bucket - age_in_buckets

      compacted_key = "c:#{key}"
      already = @last_seen[compacted_key]? || 0_i64

      if cutoff > already
        compact_range_unified(name, metric, already, cutoff, size)
        @last_seen[compacted_key] = cutoff
      end

      @last_seen[key] = current_bucket
    end

    private def compact_range_unified(name : String, metric : String, start_num : Int64, end_num : Int64, size : Time::Span)
      return if start_num >= end_num

      start_time = bucket_start_from_number(start_num, size)
      end_time = bucket_start_from_number(end_num, size)

      rows = [] of NamedTuple(value: Float64?, avg: Float64?, k: Int32, dev: Float64, min: Float64?, max: Float64?, from_ts: Time, to_ts: Time, resolved_at: Time)
      @db.connection.query(
        "SELECT value, avg, k, dev, min, max, from_ts, to_ts, resolved_at FROM sensors WHERE name = ? AND metric = ? AND from_ts >= ? AND from_ts < ? ORDER BY from_ts ASC",
        name, metric, start_time, end_time
      ) do |rs|
        rs.each do
          rows << {value: rs.read(Float64?), avg: rs.read(Float64?), k: rs.read(Int32), dev: rs.read(Float64),
                   min: rs.read(Float64?), max: rs.read(Float64?), from_ts: rs.read(Time), to_ts: rs.read(Time),
                   resolved_at: rs.read(Time)}
        end
      end
      return if rows.empty?

      groups = {} of Int64 => Array(typeof(rows.first))
      rows.each do |r|
        num = floor_to(r[:from_ts], size)
        (groups[num] ||= [] of typeof(rows.first)) << r
      end

      @db.connection.exec(
        "DELETE FROM sensors WHERE name = ? AND metric = ? AND from_ts >= ? AND from_ts < ?",
        name, metric, start_time, end_time
      )

      groups.each do |num, g_rows|
        bs = bucket_start_from_number(num, size)
        be = bs + size
        m_k, m_avg, m_dev, m_min, m_max, m_val = merge_welford(g_rows)
        midpoint = bs + (size / 2)

        @db.connection.exec(
          "INSERT INTO sensors (name, metric, value, avg, k, dev, min, max, from_ts, to_ts, resolved_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          name, metric, m_val, m_avg, m_k, m_dev, m_min, m_max, bs, be, midpoint
        )
      end
    end

    private def merge_welford(rows : Array) : {Int32, Float64, Float64, Float64, Float64, Float64?}
      m_k = 0
      m_avg = 0.0
      m_dev = 0.0
      m_min = Float64::MAX
      m_max = Float64::MIN
      m_val = nil

      rows.each do |r|
        rk = r[:k]
        rv = r[:avg] || 0.0
        rmin = r[:min] || Float64::MAX
        rmax = r[:max] || Float64::MIN

        if m_k == 0
          m_k = rk
          m_avg = rv
          m_dev = r[:dev]
          m_val = r[:value]
        else
          delta = rv - m_avg
          new_k = m_k + rk
          m_dev = m_dev + r[:dev] + delta * delta * m_k * rk / new_k
          m_avg = m_avg + delta * rk / new_k
          m_k = new_k
          m_val = r[:value] if r[:value]
        end

        m_min = Math.min(m_min, rmin)
        m_max = Math.max(m_max, rmax)
      end

      {m_k, m_avg, m_dev, m_min, m_max, m_val}
    end

    private def purge_old(now : Time)
      cutoff = now - @purge_age
      @db.connection.exec("DELETE FROM sensors WHERE from_ts < ?", cutoff)
    end

    private def floor_to(ts : Time, span : Time::Span) : Int64
      ts.to_unix // span.total_seconds.to_i64
    end

    private def bucket_start_from_number(num : Int64, span : Time::Span) : Time
      Time.unix(num * span.total_seconds.to_i64)
    end
  end
end
