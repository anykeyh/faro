#!/bin/sh
# Alive check probe for Faro.
#
# Checks that all configured adapters have _alive = 1.0.
# Requires FARO_ADAPTERS to be set to a comma-separated list of adapter names.
# Uses FARO_PORT (default 3000) to reach the local API.
#
# Returns JSON: healthy (0 or 1)

set -eo pipefail

ADAPTERS="${FARO_ADAPTERS}"
PORT="${FARO_PORT:-3000}"

if [ -z "$ADAPTERS" ]; then
  echo '{"healthy": 0}'
  exit 0
fi

all_alive=1

IFS=","
for name in $ADAPTERS; do
  # Trim whitespace
  name=$(echo "$name" | xargs)
  [ -z "$name" ] && continue

  # Fetch latest data for this adapter
  json=$(curl -s "http://127.0.0.1:${PORT}/api/sensors/$(echo "$name" | sed 's/ /%20/g')" 2>/dev/null) || true

  # Extract the last _alive value from the series
  alive=$(echo "$json" | awk -F'"' '
    /"_alive"/ { in_alive = 1; next }
    in_alive && /"value"/ {
      gsub(/.*"value":|[}].*/, "")
      print
      exit
    }
  ' 2>/dev/null)

  # Default to 0 if we couldn't parse it
  if [ -z "$alive" ]; then
    alive=0
  fi

  # Convert to integer for comparison
  alive_int=$(awk "BEGIN {print int($alive + 0.5)}")

  if [ "$alive_int" -ne 1 ]; then
    all_alive=0
    break
  fi
done

echo "{\"healthy\": ${all_alive}}"
