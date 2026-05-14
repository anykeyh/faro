#!/usr/bin/env bash
# Swap probe for Faro.
#
# Returns JSON: swap_total_kb, swap_used_kb, swap_free_kb
# Shares /proc/meminfo parsing with memory.sh when combined.

set -eo pipefail

eval "$(awk '
  /^SwapTotal:/ { total=$2 }
  /^SwapFree:/  { free=$2 }
  END {
    used = total - free
    printf "swap_total=%.0f swap_free=%.0f swap_used=%.0f", total, free, used
  }
' /proc/meminfo)"

echo "{\"swap_total_kb\": ${swap_total}, \"swap_used_kb\": ${swap_used}, \"swap_free_kb\": ${swap_free}}"
