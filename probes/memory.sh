#!/usr/bin/env bash
# Memory usage probe for Faro.
#
# Returns JSON: usage_pct, total_kb, used_kb, free_kb, available_kb, swap_used_kb

set -eo pipefail

eval "$(awk '
  /^MemTotal:/   { total=$2 }
  /^MemFree:/    { free=$2 }
  /^MemAvailable:/ { avail=$2 }
  /^SwapTotal:/  { swap_total=$2 }
  /^SwapFree:/   { swap_free=$2 }
  END {
    used = total - avail
    pct = (total > 0) ? (used * 100 / total) : 0
    swap_used = swap_total - swap_free
    printf "total=%.0f free=%.0f avail=%.0f used=%.0f pct=%.1f swap_used=%.0f", total, free, avail, used, pct, swap_used
  }
' /proc/meminfo)"

echo "{\"usage_pct\": ${pct}, \"total_kb\": ${total}, \"used_kb\": ${used}, \"free_kb\": ${free}, \"available_kb\": ${avail}, \"swap_used_kb\": ${swap_used}}"
