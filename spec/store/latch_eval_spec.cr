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

{% for backend in (flag?(:duckdb) ? [:sqlite, :duckdb] : [:sqlite]) %}

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

# ── Integration tests ──────────────────────────────────────

private def build_store_and_config(yaml : String) : NamedTuple(store: Faro::Store::Bucketing, config: Faro::Config)
  config = Faro::Config.from_yaml(yaml)
  db = Faro::Store::Db.new(config.db)
  db.setup_schema
  store = Faro::Store::Bucketing.new(db)
  {store: store, config: config}
end

describe "Threshold integration" do
  it "opens latch when an above-threshold value is written" do
    yaml = <<-YAML
      db: "sqlite3://:memory:"
      thresholds:
        - name: test-adapter
          metric: test-adapter.test_metric
          latches:
            - name: failing
              set: 50
              release: 10
    YAML
    result = build_store_and_config(yaml)
    store = result[:store]
    config = result[:config]
    now = Time.utc

    # Write below threshold — should not trigger
    store.write("test-adapter", {"test_metric" => 30.0}, now)
    config.thresholds.each do |t|
      t.latches.each do |l|
        store.evaluate_latch(t.name, t.metric.split(".")[1], l.name,
          set: l.set, release: l.release, value: 30.0, sustain: l.sustain, now: now)
      end
    end
    store.latch_open?("test-adapter", "failing").should be_false

    # Write above set — should trigger
    store.write("test-adapter", {"test_metric" => 80.0}, now + 1.second)
    config.thresholds.each do |t|
      t.latches.each do |l|
        store.evaluate_latch(t.name, t.metric.split(".")[1], l.name,
          set: l.set, release: l.release, value: 80.0, sustain: l.sustain, now: now + 1.second)
      end
    end
    store.latch_open?("test-adapter", "failing").should be_true

    store.close
  end

  it "opens below-latch when value drops below set" do
    yaml = <<-YAML
      db: "sqlite3://:memory:"
      thresholds:
        - name: alive-adapter
          metric: alive-adapter._alive
          latches:
            - name: dead
              set: 0.5
              release: 0.9
    YAML
    result = build_store_and_config(yaml)
    store = result[:store]
    config = result[:config]
    now = Time.utc

    store.write("alive-adapter", {"_alive" => 0.0}, now)
    config.thresholds.each do |t|
      t.latches.each do |l|
        store.evaluate_latch(t.name, t.metric.split(".")[1], l.name,
          set: l.set, release: l.release, value: 0.0, sustain: l.sustain, now: now)
      end
    end
    store.latch_open?("alive-adapter", "dead").should be_true

    store.close
  end
end
