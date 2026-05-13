#!/usr/bin/env bash
# PostgreSQL health check probe for Faro.
#
# Returns JSON metrics: alive (0/1), connections, replication_lag.
# On failure, returns alive=0 instead of exiting non-zero so the
# threshold system can alert on it.
#
# Environment (all optional):
#   PG_URI          — connection string (default: postgresql://localhost:5432/postgres)
#   PG_TIMEOUT      — psql query timeout in seconds (default: 5)

set -eo pipefail

PG_URI="${PG_URI:-postgresql://localhost:5432/postgres}"
PG_TIMEOUT="${PG_TIMEOUT:-5}"

alive=0
connections=0
replication_lag=0

# Try a fast connectivity check
if psql "$PG_URI" -c "SELECT 1" -t -A -q -o /dev/null 2>/dev/null; then
  alive=1
  connections=$(PGPASSWORD="" psql "$PG_URI" -t -A -c \
    "SELECT count(*) FROM pg_stat_activity" 2>/dev/null || echo 0)
  replication_lag=$(PGPASSWORD="" psql "$PG_URI" -t -A -c \
    "SELECT extract(epoch FROM now() - pg_last_xact_replay_timestamp())" 2>/dev/null || echo 0)
fi

echo "{\"alive\": ${alive}, \"connections\": ${connections}, \"replication_lag\": ${replication_lag}}"
