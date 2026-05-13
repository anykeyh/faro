#!/usr/bin/env bash
# CPU usage probe for Faro.
#
# Returns JSON: usage_pct, user, system, idle, iowait
#
# Reads /proc/stat over two samples to compute delta percentages.

set -eo pipefail

INTERVAL="${CPU_INTERVAL:-0.5}"

read_cpu() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat
}

old=$(read_cpu)
sleep "$INTERVAL"
new=$(read_cpu)

# Compute deltas
compute() {
  local old_ary=($old)
  local new_ary=($new)
  local total_old=0 total_new=0
  for v in "${old_ary[@]}"; do total_old=$((total_old + v)); done
  for v in "${new_ary[@]}"; do total_new=$((total_new + v)); done
  local delta=$((total_new - total_old))
  if [ "$delta" -eq 0 ]; then delta=1; fi

  local user=$(( (new_ary[0] - old_ary[0]) * 100 / delta ))
  local nice=$(( (new_ary[1] - old_ary[1]) * 100 / delta ))
  local system=$(( (new_ary[2] - old_ary[2]) * 100 / delta ))
  local idle=$(( (new_ary[3] - old_ary[3]) * 100 / delta ))
  local iowait=$(( (new_ary[4] - old_ary[4]) * 100 / delta ))
  local usage=$(( user + nice + system ))

  echo "{\"usage_pct\": ${usage}, \"user_pct\": ${user}, \"system_pct\": ${system}, \"idle_pct\": ${idle}, \"iowait_pct\": ${iowait}}"
}

compute
