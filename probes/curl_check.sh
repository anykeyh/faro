#!/bin/sh
# HTTP latency probe for Faro.
#
# Returns JSON: alive (0/1), status_code, time_total_ms, time_connect_ms.
# On failure returns alive=0 and exits 0.

set -eo pipefail

URL="${CURL_URL}"
TIMEOUT="${CURL_TIMEOUT:-10}"

if [ -z "$URL" ]; then
  echo '{"alive": 0, "status_code": 0, "time_total_ms": 0, "time_connect_ms": 0}'
  exit 0
fi

alive=0
status_code=0
time_total=0
time_connect=0

# curl still works in minimal environments (busybox, alpine)
if output=$(curl -s -o /dev/null -w "%{http_code}\t%{time_total}\t%{time_connect}" --max-time "$TIMEOUT" "$URL" 2>/dev/null); then
  status_code=$(echo "$output" | awk '{print $1}')
  total=$(echo "$output" | awk '{print $2}')
  connect=$(echo "$output" | awk '{print $3}')

  time_total=$(awk "BEGIN {printf \"%.0f\", ${total:-0} * 1000}")
  time_connect=$(awk "BEGIN {printf \"%.0f\", ${connect:-0} * 1000}")

  if [ -n "$status_code" ] && [ "$status_code" -ge 200 ] && [ "$status_code" -lt 400 ]; then
    alive=1
  fi
fi

echo "{\"alive\": ${alive}, \"status_code\": ${status_code:-0}, \"time_total_ms\": ${time_total:-0}, \"time_connect_ms\": ${time_connect:-0}}"
