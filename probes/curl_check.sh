#!/usr/bin/env bash
# HTTP latency probe for Faro.
#
# Returns JSON: alive (0/1), status_code, time_total_ms, time_connect_ms.
# On failure returns alive=0 and exits 0.
#
# Environment:
#   CURL_URL       — URL to fetch (required, no default)
#   CURL_TIMEOUT   — max time in seconds (default: 10)

set -eo pipefail

URL="${CURL_URL:?CURL_URL is required}"
TIMEOUT="${CURL_TIMEOUT:-10}"

alive=0
status_code=0
time_total=0
time_connect=0

if output=$(curl -s -o /dev/null -w "%{http_code}\t%{time_total}\t%{time_connect}" --max-time "$TIMEOUT" "$URL" 2>/dev/null); then
  IFS=$'\t' read -r code total connect <<< "$output"
  status_code=${code:-0}
  time_total=$(echo "${total:-0} * 1000" | bc 2>/dev/null || echo 0)
  time_connect=$(echo "${connect:-0} * 1000" | bc 2>/dev/null || echo 0)
  # Consider any 2xx or 3xx as alive
  if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 400 ]; then
    alive=1
  fi
fi

echo "{\"alive\": ${alive}, \"status_code\": ${status_code}, \"time_total_ms\": ${time_total}, \"time_connect_ms\": ${time_connect}}"
