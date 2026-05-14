#!/usr/bin/env bash
# System metadata probe for Faro.
#
# Returns JSON: uptime_seconds, logged_users, entropy_avail, clock_utc
# All values are numbers. No strings.

set -eo pipefail

uptime=$(awk '{print $1}' /proc/uptime)
entropy=$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo 0)
users=$(who 2>/dev/null | wc -l)
clock=$(date -u +%s)

echo "{\"uptime_seconds\": ${uptime}, \"logged_users\": ${users}, \"entropy_avail\": ${entropy}, \"clock_utc\": ${clock}}"
