#!/usr/bin/env bash
# Redis health check probe for Faro.
#
# Returns JSON: alive (0/1), connections, used_memory_bytes.
# On failure returns alive=0 and exits 0 so thresholds can trigger.
#
# Environment:
#   REDIS_URI      — redis host:port (default: localhost:6379)

set -eo pipefail

REDIS_URI="${REDIS_URI:-localhost:6379}"

alive=0
connections=0
memory=0

if redis-cli -u "$REDIS_URI" ping 2>/dev/null | grep -q PONG; then
  alive=1
  connections=$(redis-cli -u "$REDIS_URI" INFO clients 2>/dev/null | grep "connected_clients:" | cut -d: -f2 || echo 0)
  memory=$(redis-cli -u "$REDIS_URI" INFO memory 2>/dev/null | grep "used_memory:" | cut -d: -f2 || echo 0)
fi

echo "{\"alive\": ${alive}, \"connections\": ${connections}, \"used_memory_bytes\": ${memory}}"
