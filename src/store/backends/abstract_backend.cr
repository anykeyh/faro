require "db"

module Faro::Store
  # Abstract base for database backends.
  abstract class AbstractBackend
    BUCKET_SIZE = 1.minute

    abstract def connection : DB::Connection

    abstract def setup_schema : Nil
    abstract def write(adapter_name : String, data : Hash(String, Float64), timestamp : Time) : Nil
    abstract def query(adapter_name : String, since : Time, finish : Time) : Array(NamedTuple(
      metric: String, value: Float64?, avg: Float64?, k: Int32, dev: Float64,
      min: Float64?, max: Float64?, from_ts: Time, to_ts: Time, resolved_at: Time))
    abstract def list_names : Array(NamedTuple(name: String, metric: String))
    abstract def latest_value(adapter_name : String, metric : String) : Float64?
    abstract def latch_open?(threshold_name : String, latch_name : String) : Bool
    abstract def open_latch(threshold_name : String, latch_name : String, metric : String, value : Float64, now : Time) : Nil
    abstract def close_latch(threshold_name : String, latch_name : String, value : Float64, now : Time) : Nil
    abstract def open_latches : Array(NamedTuple(name: String, latch: String, metric: String, value: Float64, from_ts: Time))
    abstract def clear_data : Nil
    abstract def close : Nil

    protected def read_existing(name, metric, bucket_start)
      existing = nil
      @connection.query("SELECT k, avg, dev, min, max FROM sensors WHERE name = ? AND metric = ? AND from_ts = ?",
        name, metric, bucket_start) do |rs|
        rs.each { existing = {k: rs.read(Int32), avg: rs.read(Float64), dev: rs.read(Float64), min: rs.read(Float64), max: rs.read(Float64)} }
      end
      existing
    end

    protected def bucket_floor(ts : Time) : Time
      span = ts - Time::UNIX_EPOCH
      floored = span - (span.total_seconds % BUCKET_SIZE.total_seconds).seconds
      Time::UNIX_EPOCH + floored
    end
  end
end
