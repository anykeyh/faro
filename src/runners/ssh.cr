require "./runner"

# Runs a probe script on a remote host via SSH.
# The script file is piped via stdin.
#
# Invocation:
#   ssh <host> bash -s -- <args>
#   <script content>               (via stdin)
#
# Config:
#   via:
#     type: ssh
#     host: user@hostname
class Faro::Runners::SSH < Faro::Runner
  def run(path : String, args : Array(String)? = nil, env : Hash(String, String)? = nil, via : Config::ViaConfig? = nil) : RunnerResult
    host = via.try(&.host)
    unless host
      return RunnerResult.new(stdout: "", stderr: "ssh runner requires host:", exit_code: -1)
    end

    script_content = File.read(path)

    stdin = IO::Memory.new(script_content)
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    argv = ["ssh", host, "bash", "-s", "--"]
    (args || [] of String).each { |a| argv << a }

    status = Process.run(argv, env: env, input: stdin, output: stdout, error: stderr)

    RunnerResult.new(
      stdout: stdout.to_s,
      stderr: stderr.to_s,
      exit_code: status.exit_code,
      signaled: !status.normal_exit?
    )
  rescue ex
    RunnerResult.new(stdout: "", stderr: "ssh failed: #{ex.message}", exit_code: -1)
  end
end
