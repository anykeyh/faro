require "spec"
require "json"
require "../src/probes"

describe Faro::EmbeddedProbes do
  it "has all expected probes" do
    Faro::EmbeddedProbes::PROBES.keys.sort!.should eq [
      "cpu", "curl_check", "disk", "gpu", "load",
      "memory", "network", "processes", "swap",
      "system", "thermal",
    ]
  end

  it "resolves $cpu to a non-empty script" do
    script = Faro::EmbeddedProbes.resolve("$cpu")
    script.should_not be_nil
    s = script.as(String)
    s.should_not be_empty
    s.should contain("#!/bin/sh")
  end

  it "returns nil for unknown $name" do
    Faro::EmbeddedProbes.resolve("$nonexistent").should be_nil
  end

  it "returns nil for plain path (not $name)" do
    Faro::EmbeddedProbes.resolve("./probes/cpu.sh").should be_nil
  end
end

# Helper: run a shell script and return [stdout, stderr, Process::Status]
def run_script(script : String, env : Hash(String, String) = {} of String => String)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run("bash", input: IO::Memory.new(script), output: stdout, error: stderr, env: env)
  {stdout.to_s, stderr.to_s, status}
end

# Validates that a probe returns valid JSON with numeric values.
def verify_numeric_probe(name : String, script : String, env : Hash(String, String) = {} of String => String)
  it "#{name} produces valid JSON with numeric values" do
    stdout, stderr, status = run_script(script, env: env)
    status.success?.should be_true, "probe '#{name}' failed: #{stderr}"

    json = JSON.parse(stdout)
    json.should be_a(JSON::Any)

    json.as_h.each do |key, val|
      case val
      when JSON::Any
        (val.as_f? || val.as_i?).should_not be_nil,
          "probe '#{name}' key '#{key}' is not numeric: #{val.raw}"
      else
        fail "probe '#{name}' key '#{key}' has unexpected type: #{val.class}"
      end
    end
  end
end

describe "default probes (numeric JSON)" do
  verify_numeric_probe("cpu", Faro::EmbeddedProbes::PROBES["cpu"])
  verify_numeric_probe("memory", Faro::EmbeddedProbes::PROBES["memory"])
  verify_numeric_probe("disk", Faro::EmbeddedProbes::PROBES["disk"])
  verify_numeric_probe("load", Faro::EmbeddedProbes::PROBES["load"])
  verify_numeric_probe("network", Faro::EmbeddedProbes::PROBES["network"])
  verify_numeric_probe("swap", Faro::EmbeddedProbes::PROBES["swap"])
  verify_numeric_probe("processes", Faro::EmbeddedProbes::PROBES["processes"])
  verify_numeric_probe("system", Faro::EmbeddedProbes::PROBES["system"])
  verify_numeric_probe("thermal", Faro::EmbeddedProbes::PROBES["thermal"])

  it "gpu probe returns valid JSON (empty {} if no GPU, or numeric values)" do
    script = Faro::EmbeddedProbes::PROBES["gpu"]
    stdout, stderr, status = run_script(script)
    status.success?.should be_true, "gpu probe failed: #{stderr}"

    json = JSON.parse(stdout)
    json.should be_a(JSON::Any)

    if json.as_h.empty?
      # No GPU — empty JSON is acceptable
    else
      json.as_h.each do |key, val|
        case val
        when JSON::Any
          (val.as_f? || val.as_i?).should_not be_nil,
            "gpu probe key '#{key}' is not numeric: #{val.raw}"
        else
          fail "gpu probe key '#{key}' has unexpected type: #{val.class}"
        end
      end
    end
  end

  it "curl_check produces valid JSON" do
    script = Faro::EmbeddedProbes::PROBES["curl_check"]
    stdout, stderr, status = run_script(script, env: {"CURL_URL" => "http://127.0.0.1:1", "CURL_TIMEOUT" => "2"})
    status.success?.should be_true, "curl_check failed: #{stderr}"

    json = JSON.parse(stdout)
    json.should be_a(JSON::Any)
    json["alive"].should_not be_nil
  end
end
