# Embedded default probes.
#
# Probes in probes/ are compiled into the binary at build time.
# They can be referenced via `$name` in the config file:
#
#   adapters:
#     - name: cpu
#       run: $cpu
#
# Available probes (all system-level):
#   cpu, memory, disk, load, network, swap, processes, system, thermal,
#   gpu, curl_check

module Faro
  module EmbeddedProbes
    # Map of $name → shell script content.
    PROBES = {
      "cpu"         => {{ read_file("probes/cpu.sh") }},
      "memory"      => {{ read_file("probes/memory.sh") }},
      "disk"        => {{ read_file("probes/disk.sh") }},
      "load"        => {{ read_file("probes/load.sh") }},
      "network"     => {{ read_file("probes/network.sh") }},
      "swap"        => {{ read_file("probes/swap.sh") }},
      "processes"   => {{ read_file("probes/processes.sh") }},
      "system"      => {{ read_file("probes/system.sh") }},
      "thermal"     => {{ read_file("probes/thermal.sh") }},
      "gpu"         => {{ read_file("probes/gpu.sh") }},
      "curl_check"  => {{ read_file("probes/curl_check.sh") }},
    }

    # If `run` starts with `$`, resolve it to the embedded probe script.
    # Returns the script content as a String, or nil if unknown.
    def self.resolve(run : String?) : String?
      return nil if run.nil?
      if run.starts_with?('$')
        name = run.lchop('$')
        if (script = PROBES[name]?)
          script
        else
          nil
        end
      else
        # Plain path — read from filesystem (handled by runner)
        nil
      end
    end
  end
end
