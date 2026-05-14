#!/usr/bin/env bash
# Disk usage probe for Faro.
#
# Returns JSON with per-mount metrics. Each mount gets:
#   _slash_root_usage_pct (0-1)
# And optional: _slash_root_total_bytes, _slash_root_used_bytes
#
# Skips tmpfs, devtmpfs, squashfs, overlay, proc, sysfs, cgroup.

set -eo pipefail

first=true
echo -n "{"

df -B1 --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs \
       --exclude-type=overlay --exclude-type=proc --exclude-type=sysfs \
       --exclude-type=cgroup 2>/dev/null | tail -n +2 | while read -r fs total used avail pct mount; do
  # Sanitize mount path for JSON key
  safe=$(echo "$mount" | sed 's|/|_slash_|g; s|-|_dash_|g')
  pct_val=$(echo "$pct" | tr -d '%')
  frac=$(awk "BEGIN {printf \"%.3f\", ${pct_val} / 100}")

  [ "$first" = true ] && first=false || echo -n ","
  echo -n "\"${safe}_usage_pct\": ${frac}"
  echo -n ", \"${safe}_total_bytes\": ${total}"
  echo -n ", \"${safe}_used_bytes\": ${used}"
  echo -n ", \"${safe}_available_bytes\": ${avail}"
done

echo "}"
