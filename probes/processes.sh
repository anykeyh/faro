#!/usr/bin/env bash
# Processes probe for Faro.
#
# Returns JSON: running, sleeping, zombie, blocked, total

set -eo pipefail

total=0; running=0; sleeping=0; zombie=0; blocked=0

while IFS= read -r line; do
  total=$((total + 1))
  state=$(echo "$line" | awk '{print $3}')
  case "$state" in
    R) running=$((running + 1)) ;;
    S|D|I) sleeping=$((sleeping + 1)) ;;
    Z) zombie=$((zombie + 1)) ;;
  esac
done < <(ps -eo stat 2>/dev/null | tail -n +2)

# /proc/stat also has process counts
procs_running=$(grep procs_running /proc/stat 2>/dev/null | awk '{print $2}' || echo 0)
procs_blocked=$(grep procs_blocked /proc/stat 2>/dev/null | awk '{print $2}' || echo 0)

echo "{\"total\": ${total}, \"running\": ${running}, \"sleeping\": ${sleeping}, \"zombie\": ${zombie}, \"blocked\": ${procs_blocked}}"
