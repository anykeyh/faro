#!/usr/bin/env bash
# Thermal probe for Faro.
#
# Returns JSON: x86_pkg_temp (if available), and per-zone temps
# All values are Celsius.

set -eo pipefail

first=true
echo -n "{"

# CPU temperature from thermal zones
for zonepath in /sys/class/thermal/thermal_zone*/temp; do
  [ -f "$zonepath" ] || continue
  temp=$(cat "$zonepath" 2>/dev/null)
  [ -z "$temp" ] && continue
  type=$(cat "$(dirname "$zonepath")/type" 2>/dev/null)
  [ -z "$type" ] && type="zone_$(basename $(dirname $zonepath) | tr -cd '0-9')"
  temp_c=$(awk "BEGIN {printf \"%.1f\", $temp / 1000}")

  [ "$first" = true ] && first=false || echo -n ","
  echo -n "\"${type}\": ${temp_c}"
done

# Disk temperature via smartctl (if available)
if command -v smartctl &>/dev/null; then
  for disk in /dev/sd? /dev/nvme[0-9]n[0-9]; do
    [ -b "$disk" ] || continue
    disk_name=$(basename "$disk")
    temp=$(smartctl -A "$disk" 2>/dev/null | awk '/Temperature_Celsius|Current Temperature/ {print $NF; exit}' || true)
    if [ -n "$temp" ]; then
      if [ "$temp" -eq "$temp" ] 2>/dev/null; then
        echo -n ", \"${disk_name}_temp\": ${temp}"
      fi
    fi
  done
fi

echo "}"
