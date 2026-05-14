require "../spec_helper"
require "../../src/store/bucketing"

def fresh_bucketing(backend : Symbol = :sqlite) : Faro::Store::Bucketing
  uri = case backend
        when :sqlite
          "sqlite3://:memory:?max_pool_size=1"
        when :duckdb
          "duckdb://:memory:?max_pool_size=1"
        else
          raise "Unknown backend: #{backend}"
        end
  db = Faro::Store::Db.new(uri)
  db.setup_schema
  Faro::Store::Bucketing.new(db)
end

{% for backend in [:sqlite, :duckdb] %}

describe "Faro::Store::Bucketing ({{backend.id}})" do
  # ── Raw writes ──────────────────────────────────────────────────────────────

  it "stores raw data with exact timestamp and k=1" do
    s = fresh_bucketing({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 7)
    s.write("cpu", {"usage" => 45.0}, t)

    rows = s.query("cpu", t - 1.second, t + 1.second)
    rows.size.should eq 1
    r = rows.first
    r[:metric].should eq "usage"
    r[:k].should eq 1
    r[:avg].not_nil!.should be_close(45.0, 1e-9)
    r[:from_ts].should eq t
    s.close
  end

  it "stores multiple metrics in one write" do
    s = fresh_bucketing({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"user" => 10.0, "system" => 5.0}, t)

    rows = s.query("cpu", t - 1.second, t + 1.second)
    rows.size.should eq 2
    rows.map(&.[:metric]).sort.should eq ["system", "user"]
    s.close
  end

  # ── 1-minute compaction (old enough to pass age threshold) ────────────

  it "compacts raw rows into a 1-minute bucket when data is older than 5 min" do
    s = fresh_bucketing({{backend}})
    # Write two raw samples in minute 12:00
    t1 = Time.utc(2026, 6, 1, 12, 0, 10)
    t2 = Time.utc(2026, 6, 1, 12, 0, 50)
    s.write("cpu", {"x" => 2.0}, t1)
    s.write("cpu", {"x" => 4.0}, t2)

    # Both should still be raw (same minute bucket, no boundary crossed yet)
    rows = s.query("cpu", t1 - 1.second, t2 + 1.second)
    rows.size.should eq 2

    # Jump 6 minutes ahead — this crosses the 1m boundary AND data is now > 5 min old
    t3 = Time.utc(2026, 6, 1, 12, 6, 5)
    s.write("cpu", {"x" => 6.0}, t3)

    # The two raw rows in 12:00 should now be compacted into one 1m bucket
    rows = s.query("cpu", Time.utc(2026, 6, 1, 12, 0, 0),
                   Time.utc(2026, 6, 1, 12, 7, 0))
    rows.size.should eq 2

    compacted = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 12, 0, 0) }
    compacted.should_not be_nil
    compacted.not_nil![:k].should eq 2
    compacted.not_nil![:avg].not_nil!.should be_close(3.0, 1e-9)
    compacted.not_nil![:min].not_nil!.should be_close(2.0, 1e-9)
    compacted.not_nil![:max].not_nil!.should be_close(4.0, 1e-9)
    s.close
  end

  it "1-minute bucket is aligned to the UTC minute boundary" do
    s = fresh_bucketing({{backend}})
    t1 = Time.utc(2026, 6, 1, 12, 0, 30)
    # Jump 6 min — crosses boundary AND past age threshold
    t2 = Time.utc(2026, 6, 1, 12, 6, 10)
    s.write("cpu", {"x" => 10.0}, t1)
    s.write("cpu", {"x" => 20.0}, t2)

    compacted = s.query("cpu", Time.utc(2026, 6, 1, 12, 0, 0),
                        Time.utc(2026, 6, 1, 12, 0, 0) + 1.second)
    compacted.size.should eq 1
    compacted.first[:from_ts].should eq Time.utc(2026, 6, 1, 12, 0, 0)
    s.close
  end

  # ── Age guard: data < 5 min should NOT be compacted ───────────────────

  it "in real-time operation, 1m compacted rows appear after ~5 minutes" do
    s = fresh_bucketing({{backend}})
    base = Time.utc(2026, 6, 1, 12, 0, 0)

    # Simulate writes every 5 seconds for 10 minutes (120 writes)
    120.times do |i|
      s.write("cpu", {"x" => i.to_f}, base + i.seconds * 5)
    end

    finish = base + (119 * 5).seconds + 1.second
    rows = s.query("cpu", base - 1.second, finish)

    # Data in the first 5 minutes should still be raw (k=1)
    recent_rows = rows.select { |r| r[:from_ts] >= base + (5 * 60).seconds }
    recent_rows.each { |r| r[:k].should eq 1 }

    # Data older than 5 minutes should be compacted into 1m buckets (k > 1)
    old_rows = rows.select { |r| r[:from_ts] < base + (5 * 60).seconds && r[:k] > 1 }
    old_rows.size.should be > 0

    s.close
  end

  it "does NOT compact data newer than the tier's age threshold" do
    s = fresh_bucketing({{backend}})
    t1 = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"x" => 10.0}, t1)

    # Cross 1-minute boundary at 12:01 — 12:00 is only 60s old, age=5min, should NOT compact
    t2 = Time.utc(2026, 6, 1, 12, 1, 0)
    s.write("cpu", {"x" => 20.0}, t2)

    rows = s.query("cpu", t1 - 1.second, t2 + 1.second)
    rows.size.should eq 2
    rows.each { |r| r[:k].should eq 1 }

    s.close
  end

  it "does NOT compact raw data within the last 5 minutes even after many writes" do
    s = fresh_bucketing({{backend}})
    base = Time.utc(2026, 6, 1, 12, 0, 0)

    # Write every 5 seconds for 3 minutes — all within last 5 min, nothing compacted
    36.times do |i|
      s.write("cpu", {"x" => i.to_f}, base + i.seconds * 5)
    end

    finish = base + (36 * 5 + 1).seconds
    rows = s.query("cpu", base - 1.second, finish)

    rows.size.should eq 36
    rows.each { |r| r[:k].should eq 1 }

    s.close
  end

  # ── 5-minute compaction (data old enough) ─────────────────────────────

  it "compacts 1m buckets into a 5-minute bucket when data is older than 1h" do
    s = fresh_bucketing({{backend}})
    # Fill two 1-minute buckets at 11:00 (1h+ ago from target)
    s.write("cpu", {"x" => 1.0}, Time.utc(2026, 6, 1, 11, 55, 10))
    s.write("cpu", {"x" => 2.0}, Time.utc(2026, 6, 1, 11, 56, 5))  # crosses 1m → compacts 11:55

    s.write("cpu", {"x" => 3.0}, Time.utc(2026, 6, 1, 11, 56, 10))
    s.write("cpu", {"x" => 4.0}, Time.utc(2026, 6, 1, 11, 57, 5))  # crosses 1m → compacts 11:56

    # Now cross 5-minute boundary at 12:00 — 11:55 is 5 min old but 5m tier age is 1h
    # So this data is too young for 5m compaction. Use a much older timestamp.
    # Write at 13:00 — data at 11:55 is now 65 min old, past 1h threshold
    s.write("cpu", {"x" => 5.0}, Time.utc(2026, 6, 1, 13, 0, 5))

    # The 1m buckets at 11:55 and 11:56 should be compacted into one 5m bucket at 11:55
    rows = s.query("cpu", Time.utc(2026, 6, 1, 11, 55, 0),
                   Time.utc(2026, 6, 1, 11, 58, 0))
    five_m = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 11, 55, 0) }
    five_m.should_not be_nil
    five_m.not_nil![:k].should eq 4
    s.close
  end

  it "5-minute bucket is aligned to :00, :05, :10..." do
    s = fresh_bucketing({{backend}})
    s.write("cpu", {"x" => 1.0}, Time.utc(2026, 6, 1, 11, 55, 10))
    s.write("cpu", {"x" => 2.0}, Time.utc(2026, 6, 1, 11, 56, 5))
    s.write("cpu", {"x" => 3.0}, Time.utc(2026, 6, 1, 13, 0, 5))

    five_m = s.query("cpu", Time.utc(2026, 6, 1, 11, 55, 0),
                     Time.utc(2026, 6, 1, 11, 55, 0) + 1.second)
    five_m.size.should eq 1
    five_m.first[:from_ts].should eq Time.utc(2026, 6, 1, 11, 55, 0)
    s.close
  end

  # ── Cascade: raw → 1m → 5m ─────────────────────────────────────────────────

  it "cascades compaction: raw → 1m, then 1m → 5m when data is old enough" do
    s = fresh_bucketing({{backend}})
    # Fill minute 11:55 (65+ min ago from 13:00)
    s.write("cpu", {"x" => 10.0}, Time.utc(2026, 6, 1, 11, 55, 10))
    s.write("cpu", {"x" => 20.0}, Time.utc(2026, 6, 1, 11, 56, 5))  # crosses 1m → compacts 11:55

    s.write("cpu", {"x" => 30.0}, Time.utc(2026, 6, 1, 11, 56, 10))
    s.write("cpu", {"x" => 40.0}, Time.utc(2026, 6, 1, 11, 57, 5))  # crosses 1m → compacts 11:56

    # Cross 5-minute boundary at 13:00 — data is 65+ min old, past 1h 5m tier age
    s.write("cpu", {"x" => 50.0}, Time.utc(2026, 6, 1, 13, 0, 5))

    rows = s.query("cpu", Time.utc(2026, 6, 1, 11, 55, 0),
                   Time.utc(2026, 6, 1, 11, 58, 0))
    five_m = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 11, 55, 0) }
    five_m.should_not be_nil
    five_m.not_nil![:k].should eq 4
    five_m.not_nil![:avg].not_nil!.should be_close(25.0, 1e-9)
    s.close
  end

  # ── Welford correctness across compaction ──────────────────────────────────

  it "preserves Welford statistics through 1m compaction" do
    s = fresh_bucketing({{backend}})
    values = [3.0, 5.0, 7.0, 9.0]
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    values.each_with_index { |v, i| s.write("w", {"v" => v}, t + i.seconds) }

    # Jump 6 min ahead — crosses 1m boundary AND past age threshold
    s.write("w", {"v" => 11.0}, Time.utc(2026, 6, 1, 12, 6, 0))

    compacted = s.query("w", Time.utc(2026, 6, 1, 12, 0, 0),
                        Time.utc(2026, 6, 1, 12, 0, 0) + 1.second).first
    compacted[:k].should eq 4
    compacted[:avg].not_nil!.should be_close(6.0, 1e-9)
    pop_var = compacted[:dev] / compacted[:k]
    pop_var.should be_close(5.0, 1e-6)
    s.close
  end

  # ── Purge ──────────────────────────────────────────────────────────────────

  it "purges data older than 365 days" do
    s = fresh_bucketing({{backend}})
    old = Time.utc(2024, 1, 1, 0, 0, 0)
    recent = Time.utc(2026, 6, 1, 12, 0, 0)

    s.write("cpu", {"x" => 1.0}, old)
    s.write("cpu", {"x" => 2.0}, recent)

    s.write("cpu", {"x" => 3.0}, Time.utc(2026, 6, 1, 12, 1, 0))

    rows = s.query("cpu", old - 1.second, recent + 1.minute)
    rows.none? { |r| r[:from_ts] == old }.should be_true
    s.close
  end

  # ── Query across mixed tiers ───────────────────────────────────────────────

  it "returns rows from multiple tiers in a single query" do
    s = fresh_bucketing({{backend}})
    s.write("cpu", {"x" => 1.0}, Time.utc(2026, 6, 1, 12, 5, 30))

    s.write("cpu", {"x" => 2.0}, Time.utc(2026, 6, 1, 12, 0, 10))
    s.write("cpu", {"x" => 3.0}, Time.utc(2026, 6, 1, 12, 6, 5))

    rows = s.query("cpu", Time.utc(2026, 6, 1, 11, 0, 0),
                   Time.utc(2026, 6, 1, 13, 0, 0))
    rows.size.should eq 3
    rows.map(&.[:from_ts]).sort!
    s.close
  end

  # ── Empty data ─────────────────────────────────────────────────────────────

  it "handles empty data hash gracefully" do
    s = fresh_bucketing({{backend}})
    s.write("cpu", {} of String => Float64, Time.utc)
    s.list_names.should be_empty
    s.close
  end

  # ── Series compaction test ───────────────────────────────────────────

  it "series: recent data stays raw, old data gets compacted progressively" do
    s = fresh_bucketing({{backend}})
    base = Time.utc(2026, 6, 1, 12, 0, 0)

    # Write data every 5 seconds:
    # - First block at 11:50 (15 min ago) → should compact to 1m buckets
    # - Second block at 12:00 (now) → should stay raw

    # Old data: 11:50 through 11:54 (one raw per minute, two writes each)
    # 11:50 bucket
    s.write("cpu", {"x" => 10.0}, Time.utc(2026, 6, 1, 11, 50, 10))
    s.write("cpu", {"x" => 20.0}, Time.utc(2026, 6, 1, 11, 51, 5))  # crosses 1m, but data only 1m old → NOT compacted

    # 11:51 bucket
    s.write("cpu", {"x" => 30.0}, Time.utc(2026, 6, 1, 11, 51, 10))
    s.write("cpu", {"x" => 40.0}, Time.utc(2026, 6, 1, 11, 52, 5))  # crosses 1m, still young → NOT compacted

    # Now write at 12:10 — all 11:50-11:52 data is now 18+ min old, past 1m tier age of 5min
    s.write("cpu", {"x" => 50.0}, Time.utc(2026, 6, 1, 12, 10, 5))

    # Query the old range
    rows = s.query("cpu", Time.utc(2026, 6, 1, 11, 50, 0), Time.utc(2026, 6, 1, 11, 53, 0))

    # Should have:
    # - 1m compacted row at 11:50:00 (k=1, avg=10)
    # - 1m compacted row at 11:51:00 (k=2, avg=25)
    # - 1m compacted row at 11:52:00 (k=1, avg=40)
    rows.size.should eq 3

    r1 = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 11, 50, 0) }
    r1.should_not be_nil
    r1.not_nil![:k].should eq 1
    r1.not_nil![:avg].not_nil!.should be_close(10.0, 1e-9)

    r2 = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 11, 51, 0) }
    r2.should_not be_nil
    r2.not_nil![:k].should eq 2
    r2.not_nil![:avg].not_nil!.should be_close(25.0, 1e-9)

    r3 = rows.find { |r| r[:from_ts] == Time.utc(2026, 6, 1, 11, 52, 0) }
    r3.should_not be_nil
    r3.not_nil![:k].should eq 1
    r3.not_nil![:avg].not_nil!.should be_close(40.0, 1e-9)

    s.close
  end

  it "series: recent writes within 5 minutes all remain raw" do
    s = fresh_bucketing({{backend}})
    now = Time.utc(2026, 6, 1, 12, 0, 0)

    # Write every 5 seconds for 4 minutes
    48.times do |i|
      s.write("cpu", {"x" => i.to_f}, now + i.seconds * 5)
    end

    finish = now + (48 * 5).seconds
    rows = s.query("cpu", now - 1.second, finish + 1.second)

    # All should still be raw
    rows.size.should eq 48
    rows.each { |r| r[:k].should eq 1 }

    s.close
  end

  it "series: compacted 1m buckets have midpoint resolved_at" do
    s = fresh_bucketing({{backend}})

    # Data in 12:00 bucket (two samples)
    s.write("cpu", {"x" => 10.0}, Time.utc(2026, 6, 1, 12, 0, 10))
    s.write("cpu", {"x" => 20.0}, Time.utc(2026, 6, 1, 12, 0, 50))

    # Jump 6 min ahead to trigger compaction
    s.write("cpu", {"x" => 30.0}, Time.utc(2026, 6, 1, 12, 6, 0))

    compacted = s.query("cpu", Time.utc(2026, 6, 1, 12, 0, 0),
                        Time.utc(2026, 6, 1, 12, 0, 0) + 1.second).first

    # resolved_at should be the midpoint of the 1m bucket: 12:00:30
    compacted[:resolved_at].should eq Time.utc(2026, 6, 1, 12, 0, 30)

    s.close
  end

  # ── Delegated methods ──────────────────────────────────────────────────────

  it "delegates list_names to the underlying Db" do
    s = fresh_bucketing({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"pct" => 30.0}, t)
    s.write("mem", {"pct" => 60.0}, t)

    names = s.list_names
    names.size.should eq 2
    names.should contain({name: "cpu", metric: "pct"})
    names.should contain({name: "mem", metric: "pct"})
    s.close
  end
end

{% end %}
