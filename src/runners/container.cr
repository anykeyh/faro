require "./runner"
require "./local"
require "./docker"
require "./ssh"

class Faro::RunnerContainer
  @registry : Hash(String, Faro::Runner)

  def initialize
    @registry = {
      "local"  => Faro::Runners::Local.new,
      "docker" => Faro::Runners::Docker.new,
      "ssh"    => Faro::Runners::SSH.new,
    }
  end

  # Register a custom runner (e.g. kubectl, ssh).
  def register(type : String, runner : Faro::Runner)
    @registry[type] = runner
  end

  # Run a probe via the appropriate transport runner.
  # Returns raw output; the caller is responsible for parsing the JSON.
  def run(path : String, args : Array(String)? = nil,
          env : Hash(String, String)? = nil,
          via : Config::ViaConfig? = nil) : RunnerResult
    type = via.try(&.type) || "local"
    runner = @registry[type]?
    unless runner
      return RunnerResult.new(stdout: "", stderr: "unknown runner type: #{type}", exit_code: -1)
    end
    runner.run(path, args: args, env: env, via: via)
  end
end
