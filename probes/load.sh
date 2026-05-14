#!/usr/bin/env bash
# Load averages probe for Faro.
#
# Returns JSON: load_1m, load_5m, load_15m, tasks_running, tasks_total

set -eo pipefail

# Read /proc/loadavg once. Format: "2.52 1.73 1.56 2/2105 227309"
read -r line < /proc/loadavg
read -r load1 load5 load15 tasks rest <<< "$line"
tasks_running="${tasks%%/*}"
tasks_total="${tasks#*/}"

echo "{\"load_1m\": ${load1}, \"load_5m\": ${load5}, \"load_15m\": ${load15}, \"tasks_running\": ${tasks_running}, \"tasks_total\": ${tasks_total}}"
