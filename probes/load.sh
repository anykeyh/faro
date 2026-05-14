#!/bin/sh
# Load averages probe for Faro.
#
# Returns JSON: load_1m, load_5m, load_15m, tasks_running, tasks_total

set -eo pipefail

# /proc/loadavg format: "2.52 1.73 1.56 2/2105 227309"
line=$(cat /proc/loadavg)

load1=$(echo "$line" | awk '{print $1}')
load5=$(echo "$line" | awk '{print $2}')
load15=$(echo "$line" | awk '{print $3}')
tasks_raw=$(echo "$line" | awk '{print $4}')

tasks_running="${tasks_raw%%/*}"
tasks_total="${tasks_raw#*/}"

echo "{\"load_1m\": ${load1}, \"load_5m\": ${load5}, \"load_15m\": ${load15}, \"tasks_running\": ${tasks_running}, \"tasks_total\": ${tasks_total}}"
