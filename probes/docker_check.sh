#!/usr/bin/env bash
# Docker container reachability probe for Faro.
#
# Returns JSON: alive (0/1), state, exit_code, started_seconds_ago.
# On failure returns alive=0 and exits 0.
#
# Environment:
#   DOCKER_CONTAINER — container name or ID (required, no default)

set -eo pipefail

CONTAINER="${DOCKER_CONTAINER:?DOCKER_CONTAINER is required}"

alive=0
state="unknown"
exit_code=0
uptime=0

if docker inspect "$CONTAINER" > /dev/null 2>&1; then
  # Container exists
  state=$(docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")

  if [ "$state" = "running" ]; then
    alive=1
    uptime=$(docker inspect "$CONTAINER" --format '{{.State.StartedAt}}' 2>/dev/null | xargs -I{} date -d {} +%s 2>/dev/null)
    now=$(date +%s)
    started_seconds_ago=$(( now - uptime ))
  else
    exit_code=$(docker inspect "$CONTAINER" --format '{{.State.ExitCode}}' 2>/dev/null || echo -1)
    started_seconds_ago=0
  fi
fi

echo "{\"alive\": ${alive}, \"state\": \"${state}\", \"exit_code\": ${exit_code}, \"started_seconds_ago\": ${started_seconds_ago}}"
