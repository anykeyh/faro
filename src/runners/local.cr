require "./runner"

# Runs a probe script locally via fork-exec.
class Faro::Runners::Local < Faro::Runner
  def run(path : String, args : Array(String)? = nil, env : Hash(String, String)? = nil,
          via : Config::ViaConfig? = nil, timeout : Float64? = nil) : RunnerResult
    argv = [path] + (args || [] of String)

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    process = Process.new(argv, env: env, output: stdout, error: stderr)

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
    RunnerResult.new(stdout: "", stderr: "failed to launch: #{ex.message}", exit_code: -1)
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
