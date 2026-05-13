#!/usr/bin/env bash
# MySQL health check probe for Faro.
#
# Returns JSON: alive (0/1), connections, seconds_behind_master.
# On failure returns alive=0 and exits 0 so thresholds can trigger.
#
# Environment:
#   MYSQL_URI      — connection string (default: mysql://root@localhost:3306)

set -eo pipefail

MYSQL_URI="${MYSQL_URI:-mysql://root@localhost:3306}"

alive=0
connections=0
seconds_behind=0

if mysql "$MYSQL_URI" -e "SELECT 1" -s -N 2>/dev/null; then
  alive=1
  connections=$(mysql "$MYSQL_URI" -e "SELECT COUNT(*) FROM information_schema.processlist" -s -N 2>/dev/null || echo 0)
  seconds_behind=$(mysql "$MYSQL_URI" -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Seconds_Behind_Master" | awk '{print $2}' || echo 0)
fi

echo "{\"alive\": ${alive}, \"connections\": ${connections}, \"seconds_behind_master\": ${seconds_behind}}"
