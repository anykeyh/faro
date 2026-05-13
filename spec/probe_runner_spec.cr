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
end
