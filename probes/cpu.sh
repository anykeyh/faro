#!/bin/sh
# CPU usage probe for Faro.
#
# Returns JSON: usage_pct (0-1), user_pct (0-1), system_pct (0-1), idle_pct (0-1), iowait_pct (0-1)
# Reads /proc/stat over two samples to compute delta percentages.

set -eo pipefail

INTERVAL="${CPU_INTERVAL:-0.5}"

# read_cpu outputs the 8 fields of the first "cpu" line
old=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)
sleep "$INTERVAL"
new=$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)

# Compute deltas using awk directly
awk -v old="$old" -v new="$new" '
BEGIN {
  split(old, o)
  split(new, n)
  total_old = 0; total_new = 0
  for (i = 1; i <= 7; i++) { total_old += o[i]; total_new += n[i] }
  delta = total_new - total_old
  if (delta == 0) delta = 1

  user   = (n[1] - o[1]) / delta
  nice   = (n[2] - o[2]) / delta
  sys    = (n[3] - o[3]) / delta
  idle   = (n[4] - o[4]) / delta
  iowait = (n[5] - o[5]) / delta
  usage  = user + nice + sys

  printf "{\"usage_pct\": %.3f, \"user_pct\": %.3f, \"system_pct\": %.3f, \"idle_pct\": %.3f, \"iowait_pct\": %.3f}\n",
    usage, user, sys, idle, iowait
}'
