require "./runner"

# Runs a probe script inside a Docker container via `docker exec`.
# The script file is piped to the container's stdin as a heredoc.
#
# Invocation:
#   docker exec -i <container> bash -s -- <args>
#   <script content>               (via stdin)
class Faro::Runners::Docker < Faro::Runner
  def run(path : String, args : Array(String)? = nil, env : Hash(String, String)? = nil,
          via : Config::ViaConfig? = nil, timeout : Float64? = nil) : RunnerResult
    container = via.try(&.container)
    unless container
      return RunnerResult.new(stdout: "", stderr: "docker runner requires container:", exit_code: -1)
    end

    script_content = File.read(path)

    stdin = IO::Memory.new(script_content)
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    argv = ["docker", "exec", "-i", container, "bash", "-s", "--"]
    (args || [] of String).each { |a| argv << a }

    process = Process.new(argv, env: env, input: stdin, output: stdout, error: stderr)

    status = if timeout
               wait_with_timeout(process, timeout)
             else
               process.wait
             end

    RunnerResult.new(
      stdout: stdout.to_s,
      stderr: stderr.to_s,
      exit_code: status.exit_code,
      signaled: !status.normal_exit?
    )
  rescue ex
    RunnerResult.new(stdout: "", stderr: "docker exec failed: #{ex.message}", exit_code: -1)
  end

  private def wait_with_timeout(process : Process, timeout : Float64) : Process::Status
    done = Channel(Process::Status).new
    spawn { done.send(process.wait) }

    select
    when status = done.receive
      status
    when timeout timeout.seconds
      Process.signal(Signal::TERM, process.pid)
      select
      when status = done.receive
        status
      when timeout 2.seconds
        Process.signal(Signal::KILL, process.pid)
        done.receive rescue Process::Status.new(-1)
      end
    end
  end
end
