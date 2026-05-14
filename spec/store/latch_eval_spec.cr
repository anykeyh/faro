require "../spec_helper"
require "../../src/store/bucketing"
require "../../src/config"

def fresh_store_for_latch(backend : Symbol = :sqlite) : Faro::Store::Bucketing
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

describe "Faro::Store::Bucketing (latch eval, {{backend.id}})" do
  # ── Latch evaluation with sustain and direction ────────────────────────

  it "opens an above-latch immediately when set > release and value >= set" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: nil, now: t)

    s.latch_open?("cpu-high", "critical").should be_true
    s.close
  end

  it "opens a below-latch immediately when set < release and value <= set" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 0.0, sustain: nil, now: t)

    s.latch_open?("alive-check", "dead").should be_true
    s.close
  end

  it "closes an open above-latch when value drops below release" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: nil, now: t)
    s.latch_open?("cpu-high", "critical").should be_true

    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 65.0, sustain: nil, now: t + 10.seconds)
    s.latch_open?("cpu-high", "critical").should be_false
    s.close
  end

  it "closes an open below-latch when value rises above release" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 0.0, sustain: nil, now: t)
    s.latch_open?("alive-check", "dead").should be_true

    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 1.0, sustain: nil, now: t + 10.seconds)
    s.latch_open?("alive-check", "dead").should be_false
    s.close
  end

  it "does not open above-latch with sustain until duration elapses" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    # First write at set crossing — timer starts
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t)
    s.latch_open?("cpu-high", "critical").should be_false
    s.open_latches.size.should eq 0

    # Same value after 5 seconds — still not enough
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t + 5.seconds)
    s.latch_open?("cpu-high", "critical").should be_false

    # After 35 seconds — sustain met
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t + 35.seconds)
    s.latch_open?("cpu-high", "critical").should be_true
    s.close
  end

  it "cancels pending timer when value drops below set before sustain elapses" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t)
    s.latch_open?("cpu-high", "critical").should be_false

    # Value drops below set — timer canceled, not opened
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 80.0, sustain: 30.0, now: t + 5.seconds)
    s.latch_open?("cpu-high", "critical").should be_false

    # Even after 35 seconds, latch should remain closed (timer was canceled)
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t + 35.seconds)
    s.latch_open?("cpu-high", "critical").should be_false

    # After another 30 seconds within the new crossing
    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 95.0, sustain: 30.0, now: t + 65.seconds)
    s.latch_open?("cpu-high", "critical").should be_true
    s.close
  end

  it "works with below-latch and sustain" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    # Value drops below 0.5 — start timer
    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 0.0, sustain: 10.0, now: t)
    s.latch_open?("alive-check", "dead").should be_false

    # After 12 seconds — sustain met, latch opens
    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 0.0, sustain: 10.0, now: t + 12.seconds)
    s.latch_open?("alive-check", "dead").should be_true

    # Value recovers above release — latch closes
    s.evaluate_latch("alive-check", "_alive", "dead", set: 0.5, release: 0.9, value: 1.0, sustain: 10.0, now: t + 20.seconds)
    s.latch_open?("alive-check", "dead").should be_false
    s.close
  end

  it "does nothing for value between set and release (no crossing)" do
    s = fresh_store_for_latch({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.evaluate_latch("cpu-high", "usage_pct", "critical", set: 90.0, release: 70.0, value: 80.0, sustain: nil, now: t)
    s.latch_open?("cpu-high", "critical").should be_false
    s.open_latches.size.should eq 0
    s.close
  end
end

{% end %}
