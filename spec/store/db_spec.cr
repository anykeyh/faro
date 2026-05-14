require "../spec_helper"

{% for backend in [:sqlite, :duckdb] %}

describe "Faro::Store::Db ({{backend.id}})" do
  # ── Schema ──────────────────────────────────────────────────────────────────

  it "starts empty after setup_schema" do
    s = fresh_store({{backend}})
    s.list_names.should be_empty
    s.close
  end

  # ── Single write ────────────────────────────────────────────────────────────

  it "stores a single sample into the current bucket" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"usage_pct" => 45.0}, t)

    rows = s.query("cpu", t - 1.minute, t + 1.minute)
    rows.size.should eq 1

    r = rows.first
    r[:metric].should eq "usage_pct"
    r[:value].not_nil!.should be_close(45.0, 1e-9)
    r[:avg].not_nil!.should be_close(45.0, 1e-9)
    r[:k].should eq 1
    r[:dev].should eq 0.0
    r[:min].not_nil!.should be_close(45.0, 1e-9)
    r[:max].not_nil!.should be_close(45.0, 1e-9)
    s.close
  end

  # ── resolved_at semantics ───────────────────────────────────────────────────

  it "sets resolved_at to the exact timestamp on first sample" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 7)
    s.write("cpu", {"x" => 1.0}, t)

    row = s.query("cpu", t - 1.minute, t + 1.minute).first
    row[:resolved_at].should eq t
    s.close
  end

  it "resolves to bucket midpoint after merge (k > 1)" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 7)
    expected_mid = Time.utc(2026, 6, 1, 12, 0, 30)

    s.write("cpu", {"x" => 1.0}, t)
    s.write("cpu", {"x" => 2.0}, t + 10.seconds)

    row = s.query("cpu", t - 1.minute, t + 1.minute).first
    row[:k].should eq 2
    row[:resolved_at].should eq expected_mid
    s.close
  end

  # ── Incremental merge ───────────────────────────────────────────────────────

  it "merges multiple samples in the same bucket" do
    s = fresh_store({{backend}})
    bucket = Time.utc(2026, 6, 1, 12, 0, 0)

    s.write("cpu", {"x" => 2.0}, bucket)
    s.write("cpu", {"x" => 4.0}, bucket + 10.seconds)
    s.write("cpu", {"x" => 6.0}, bucket + 20.seconds)

    row = s.query("cpu", bucket - 1.minute, bucket + 1.minute).first
    row[:k].should eq 3
    row[:avg].not_nil!.should be_close(4.0, 1e-9)
    row[:value].not_nil!.should be_close(6.0, 1e-9)
    row[:min].not_nil!.should be_close(2.0, 1e-9)
    row[:max].not_nil!.should be_close(6.0, 1e-9)
    row[:dev].should_not eq 0.0
    s.close
  end

  # ── Bucket isolation ────────────────────────────────────────────────────────

  it "creates separate rows for different 1‑minute buckets" do
    s = fresh_store({{backend}})
    t1 = Time.utc(2026, 6, 1, 12, 0, 30)
    t2 = Time.utc(2026, 6, 1, 12, 1, 15)

    s.write("cpu", {"load" => 10.0}, t1)
    s.write("cpu", {"load" => 20.0}, t2)

    rows = s.query("cpu", t1 - 1.minute, t2 + 1.minute)
    rows.size.should eq 2
    rows[0][:k].should eq 1
    rows[0][:value].not_nil!.should be_close(10.0, 1e-9)
    rows[1][:k].should eq 1
    rows[1][:value].not_nil!.should be_close(20.0, 1e-9)
    s.close
  end

  # ── Multiple metrics per write ──────────────────────────────────────────────

  it "stores several metrics from a single collector call" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"user" => 100.0, "system" => 50.0, "idle" => 800.0}, t)

    rows = s.query("cpu", t - 1.minute, t + 1.minute)
    rows.size.should eq 3
    rows.map(&.[:metric]).sort.should eq ["idle", "system", "user"]
    s.close
  end

  # ── list_names ──────────────────────────────────────────────────────────────

  it "returns distinct (name, metric) pairs" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu",    {"pct" => 30.0}, t)
    s.write("memory", {"pct" => 60.0}, t)

    names = s.list_names
    names.size.should eq 2
    names.should contain({name: "cpu",    metric: "pct"})
    names.should contain({name: "memory", metric: "pct"})
    s.close
  end

  # ── Empty data ──────────────────────────────────────────────────────────────

  it "gracefully handles an empty data hash" do
    s = fresh_store({{backend}})
    s.write("cpu", {} of String => Float64, Time.utc)
    s.list_names.should be_empty
    s.close
  end

  # ── Welford correctness ─────────────────────────────────────────────────────

  it "computes the correct population variance via Welford" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    [3.0, 5.0, 7.0, 9.0].each { |v| s.write("welford", {"v" => v}, t) }

    row = s.query("welford", t - 1.minute, t + 1.minute).first
    row[:k].should eq 4
    row[:avg].not_nil!.should be_close(6.0, 1e-9)

    pop_var = row[:dev] / row[:k]
    pop_var.should be_close(5.0, 1e-6)
    s.close
  end

  # ── Time-window query ───────────────────────────────────────────────────────

  it "only returns rows inside the requested time window" do
    s = fresh_store({{backend}})
    b1 = Time.utc(2026, 6, 1, 12, 0, 0)
    b2 = Time.utc(2026, 6, 1, 12, 1, 0)
    b3 = Time.utc(2026, 6, 1, 12, 2, 0)

    s.write("cpu", {"load" => 1.0}, b1 + 5.seconds)
    s.write("cpu", {"load" => 2.0}, b2 + 5.seconds)
    s.write("cpu", {"load" => 3.0}, b3 + 5.seconds)

    rows = s.query("cpu", b2, b3)
    rows.size.should eq 1
    rows.first[:value].not_nil!.should be_close(2.0, 1e-9)
    s.close
  end

  # ── Latches ─────────────────────────────────────────────────────────────────

  it "starts with no latches open" do
    s = fresh_store({{backend}})
    s.latch_open?("cpu-high", "critical").should be_false
    s.open_latches.should be_empty
    s.close
  end

  it "opens a latch and reports it as open" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.open_latch("cpu-high", "critical", "cpu.usage_pct", 95.0, t)

    s.latch_open?("cpu-high", "critical").should be_true

    latches = s.open_latches
    latches.size.should eq 1
    latches.first[:name].should eq "cpu-high"
    latches.first[:latch].should eq "critical"
    latches.first[:value].should be_close(95.0, 1e-9)
    s.close
  end

  it "closes an open latch" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.open_latch("cpu-high", "critical", "cpu.usage_pct", 95.0, t)
    s.latch_open?("cpu-high", "critical").should be_true

    s.close_latch("cpu-high", "critical", 70.0, t + 10.seconds)
    s.latch_open?("cpu-high", "critical").should be_false
    s.close
  end

  it "re-opens a latch that was previously closed" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)

    s.open_latch("cpu-high", "critical", "cpu.usage_pct", 95.0, t)
    s.close_latch("cpu-high", "critical", 70.0, t + 10.seconds)
    s.latch_open?("cpu-high", "critical").should be_false

    s.open_latch("cpu-high", "critical", "cpu.usage_pct", 92.0, t + 30.seconds)
    s.latch_open?("cpu-high", "critical").should be_true
    s.open_latches.size.should eq 1
    s.close
  end

  it "returns nil for latest_value when no data exists" do
    s = fresh_store({{backend}})
    s.latest_value("cpu", "usage_pct").should be_nil
    s.close
  end

  it "returns the latest sensor value" do
    s = fresh_store({{backend}})
    t = Time.utc(2026, 6, 1, 12, 0, 0)
    s.write("cpu", {"usage_pct" => 45.0}, t)
    s.write("cpu", {"usage_pct" => 60.0}, t + 10.seconds)

    s.latest_value("cpu", "usage_pct").not_nil!.should be_close(60.0, 1e-9)
    s.close
  end
end

{% end %}
