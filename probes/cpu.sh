#!/bin/sh
# CPU usage probe for Faro.
#
# Returns JSON: usage_pct, user, system, idle, iowait
# Reads /proc/stat over two samples to compute delta percentages.

set -eo pipefail

INTERVAL="${CPU_INTERVAL:-0.5}"

# read_cpu outputs the 8 fields of the first "cpu" line
old=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)
sleep "$INTERVAL"
new=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)

# Compute deltas using awk directly (avoids bash arrays)
awk -v old="$old" -v new="$new" '
BEGIN {
  split(old, o)
  split(new, n)
  total_old = 0; total_new = 0
  for (i = 1; i <= 7; i++) { total_old += o[i]; total_new += n[i] }
  delta = total_new - total_old
  if (delta == 0) delta = 1

  user   = int((n[1] - o[1]) * 100 / delta)
  nice   = int((n[2] - o[2]) * 100 / delta)
  sys    = int((n[3] - o[3]) * 100 / delta)
  idle   = int((n[4] - o[4]) * 100 / delta)
  iowait = int((n[5] - o[5]) * 100 / delta)
  usage  = user + nice + sys

  printf "{\"usage_pct\": %d, \"user_pct\": %d, \"system_pct\": %d, \"idle_pct\": %d, \"iowait_pct\": %d}\n",
    usage, user, sys, idle, iowait
}'
