#!/usr/bin/env bash
# Memory usage probe for Faro.
#
# Returns JSON: usage_pct (0-100), usage (0-1), total_kb, used_kb, free_kb, available_kb

set -eo pipefail

eval "$(awk '
  /^MemTotal:/   { total=$2 }
  /^MemFree:/    { free=$2 }
  /^MemAvailable:/ { avail=$2 }
  END {
    used = total - avail
    pct = (total > 0) ? (used * 100 / total) : 0
    printf "total=%.0f free=%.0f avail=%.0f used=%.0f pct=%.1f", total, free, avail, used, pct
  }
' /proc/meminfo)"

usage=$(awk "BEGIN {printf \"%.3f\", ${pct} / 100}")

echo "{\"usage_pct\": ${pct}, \"usage\": ${usage}, \"total_kb\": ${total}, \"used_kb\": ${used}, \"free_kb\": ${free}, \"available_kb\": ${avail}}"
