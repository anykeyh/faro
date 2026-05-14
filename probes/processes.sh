#!/bin/sh
# Processes probe for Faro.
#
# Returns JSON: running, sleeping, zombie, blocked, total

set -eo pipefail

# Count process states from /proc/stat (fast, no subprocess per pid)
procs_running=$(grep procs_running /proc/stat 2>/dev/null | awk '{print $2}')
procs_blocked=$(grep procs_blocked /proc/stat 2>/dev/null | awk '{print $2}')

# Use ps for detailed breakdown (single invocation)
eval "$(ps -eo stat 2>/dev/null | tail -n +2 | awk '
  { total++ }
  /^R/ { running++ }
  /^[SDI]/ { sleeping++ }
  /^Z/ { zombie++ }
  END {
    printf "total=%d running=%d sleeping=%d zombie=%d", total, running, sleeping, zombie
  }
')"

echo "{\"total\": ${total:-0}, \"running\": ${running:-0}, \"sleeping\": ${sleeping:-0}, \"zombie\": ${zombie:-0}, \"blocked\": ${procs_blocked:-0}}"
