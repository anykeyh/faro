#!/usr/bin/env bash
# Disk usage probe for Faro.
#
# Returns JSON with per-mount metrics.
# Each mount gets a flattened key like:
#   _slash_root_usage_pct, _slash_root_total_bytes, _slash_root_used_bytes
#
# Skips tmpfs, devtmpfs, squashfs, overlay, proc, sysfs, cgroup.

set -eo pipefail

# Collect per-mount metrics as a JSON object
first=true
echo -n "{"

df -B1 --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs \
       --exclude-type=overlay --exclude-type=proc --exclude-type=sysfs \
       --exclude-type=cgroup 2>/dev/null | tail -n +2 | while read -r fs total used avail pct mount; do
  # Sanitize mount path for JSON key
  safe=$(echo "$mount" | sed 's|/|_slash_|g; s|-|_dash_|g')
  [ "$first" = true ] && first=false || echo -n ","
  echo -n "\"${safe}_usage_pct\": $(echo "$pct" | tr -d '%')"
  echo -n ", \"${safe}_total_bytes\": ${total}"
  echo -n ", \"${safe}_used_bytes\": ${used}"
  echo -n ", \"${safe}_available_bytes\": ${avail}"
done

echo "}"
