require "./runner"

# Runs a probe script locally via fork-exec.
class Faro::Runners::Local < Faro::Runner
  def run(path : String, args : Array(String)? = nil, env : Hash(String, String)? = nil, via : Config::ViaConfig? = nil) : RunnerResult
    argv = [path] + (args || [] of String)

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    status = Process.run(argv, env: env, output: stdout, error: stderr)

    RunnerResult.new(
      stdout: stdout.to_s,
      stderr: stderr.to_s,
      exit_code: status.exit_code,
      signaled: !status.normal_exit?
    )
  rescue ex
    RunnerResult.new(stdout: "", stderr: "failed to launch: #{ex.message}", exit_code: -1)
  end
end
