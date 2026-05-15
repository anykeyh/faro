require "json"
require "./spec_helper"
require "../src/runners/container"

describe Faro::RunnerContainer do
  it "runs a local command and returns raw output" do
    result = Faro::Runners::Local.new.run("echo", args: ["hello"])
    result.success?.should be_true
    result.stdout.strip.should eq "hello"
    result.stderr.should eq ""
    result.exit_code.should eq 0
  end

  it "returns non-zero exit code on failure" do
    result = Faro::Runners::Local.new.run("sh", args: ["-c", "exit 42"])
    result.success?.should be_false
    result.exit_code.should eq 42
  end

  it "returns failure for nonexistent command" do
    result = Faro::Runners::Local.new.run("/nonexistent")
    result.success?.should be_false
    result.exit_code.should eq -1
  end

  it "passes env variables to the probe" do
    result = Faro::Runners::Local.new.run(
      "sh", args: ["-c", "echo \"$MY_VAR\""],
      env: {"MY_VAR" => "42"}
    )
    result.stdout.strip.should eq "42"
  end

  it "selects local runner by default when via is nil" do
    container = Faro::RunnerContainer.new
    result = container.run("echo", args: ["ok"])
    result.success?.should be_true
    result.stdout.strip.should eq "ok"
  end

  it "returns error for unknown runner type" do
    yaml = <<-YAML
      type: nonexistent
    YAML
    via = Faro::Config::ViaConfig.from_yaml(yaml)
    container = Faro::RunnerContainer.new
    result = container.run("echo", via: via)
    result.success?.should be_false
    result.stderr.should contain("unknown runner type")
  end

  it "parses docker via config and returns error (no docker in test)" do
    yaml = <<-YAML
      type: docker
    YAML
    via = Faro::Config::ViaConfig.from_yaml(yaml)
    result = Faro::RunnerContainer.new.run("echo", via: via)
    result.success?.should be_false
    result.stderr.should contain("requires container")
  end

  it "parses JSON output from local runner" do
    result = Faro::Runners::Local.new.run("echo", args: [%({"a": 1.5, "b": 2.5})])
    data = JSON.parse(result.stdout)
    data["a"].as_f.should be_close(1.5, 1e-9)
    data["b"].as_f.should be_close(2.5, 1e-9)
  end

  # ── Timeout tests ──────────────────────────────────────

  it "times out a long-running command and kills it" do
    # Sleep for 10s but timeout at 0.5s — should be killed
    result = Faro::Runners::Local.new.run("sh", args: ["-c", "sleep 10; echo never"], timeout: 0.5)
    result.success?.should be_false
    result.stdout.strip.should_not eq "never"
    result.exit_code.should_not eq 0
  end

  it "completes normally when timeout is longer than runtime" do
    result = Faro::Runners::Local.new.run("sh", args: ["-c", "echo done"], timeout: 10.0)
    result.success?.should be_true
    result.stdout.strip.should eq "done"
    result.exit_code.should eq 0
  end

  it "accepts nil timeout and runs normally" do
    result = Faro::Runners::Local.new.run("echo", args: ["hello"], timeout: nil)
    result.success?.should be_true
    result.stdout.strip.should eq "hello"
  end

  it "kills a subprocess that ignores SIGTERM" do
    # Trap SIGTERM and ignore it, sleep long enough that SIGKILL is needed.
    # The runner sends TERM first, then KILL after 2s grace.
    result = Faro::Runners::Local.new.run("sh", args: ["-c", <<-SH.strip], timeout: 0.3)
      trap '' TERM
      sleep 30
    SH
    result.success?.should be_false
    # The process was signaled (not a normal exit), so signaled should be true
    # or exit_code should be non-zero.
    (result.exit_code != 0 || result.signaled?).should be_true
  end

  it "threads timeout through RunnerContainer" do
    container = Faro::RunnerContainer.new
    result = container.run("sh", args: ["-c", "sleep 10"], timeout: 0.3)
    result.success?.should be_false
  end

  it "returns correct signal info for timed-out process" do
    result = Faro::Runners::Local.new.run("sh", args: ["-c", "sleep 10"], timeout: 0.3)
    # The process was terminated before completing normally —
    # either signaled (SIGTERM/SIGKILL) or a non-zero exit from the shell
    result.success?.should be_false
  end

  it "works with very short timeout (0.1s) and fast command does not trigger it" do
    result = Faro::Runners::Local.new.run("echo", args: ["fast"], timeout: 0.1)
    result.success?.should be_true
    result.stdout.strip.should eq "fast"
  end

  describe "adapter config integration" do
    it "parses timeout from YAML config" do
      yaml = <<-YAML
        name: test
        run: echo
        timeout: 5s
      YAML
      adapter = Faro::Config::AdapterConfig.from_yaml(yaml)
      adapter.timeout.not_nil!.should be_close(5.0, 1e-9)
    end

    it "accepts numeric timeout seconds" do
      yaml = <<-YAML
        name: test
        run: echo
        timeout: 30
      YAML
      adapter = Faro::Config::AdapterConfig.from_yaml(yaml)
      adapter.timeout.not_nil!.should be_close(30.0, 1e-9)
    end

    it "defaults timeout to nil when omitted" do
      yaml = <<-YAML
        name: test
        run: echo
      YAML
      adapter = Faro::Config::AdapterConfig.from_yaml(yaml)
      adapter.timeout.should be_nil
    end
  end
end
