require "../config"

# Result of a runner execution — raw stdout/stderr and exit status.
struct Faro::RunnerResult
  getter stdout : String
  getter stderr : String
  getter exit_code : Int32
  getter signaled : Bool

  def initialize(@stdout, @stderr, @exit_code, @signaled = false)
  end

  def success?
    !@signaled && @exit_code == 0
  end
end

# Base class for all probe transport runners.
# Each subclass implements one transport (local, docker, etc.)
# and returns a RunnerResult with raw output from the probe script.
abstract class Faro::Runner
  # Run a probe script at `path` with optional `args` and `env`,
  # routed according to `via`. Returns raw stdout/stderr.
  abstract def run(path : String, args : Array(String)?, env : Hash(String, String)?, via : Config::ViaConfig?) : RunnerResult
end
