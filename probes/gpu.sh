#!/usr/bin/env bash
# GPU probe for Faro (NVIDIA only).
#
# Returns JSON: gpu_load (0-100), gpu_mem_pct (0-100),
#               gpu_mem_used_kb, gpu_mem_total_kb, gpu_temp
# All values are numbers. Returns empty JSON {} if no GPU.

set -eo pipefail

if command -v nvidia-smi &>/dev/null; then
  IFS=',' read -r load mem_used mem_total temp < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
  load=${load:-0}
  mem_used=${mem_used:-0}
  mem_total=${mem_total:-0}
  temp=${temp:-0}

  mem_pct=$(awk "BEGIN {printf \"%.0f\", ($mem_total > 0 ? $mem_used * 100 / $mem_total : 0)}")
  mem_used_kb=$(awk "BEGIN {printf \"%.0f\", $mem_used * 1024}")
  mem_total_kb=$(awk "BEGIN {printf \"%.0f\", $mem_total * 1024}")

  echo "{\"gpu_load\": ${load}, \"gpu_mem_pct\": ${mem_pct}, \"gpu_mem_used_kb\": ${mem_used_kb}, \"gpu_mem_total_kb\": ${mem_total_kb}, \"gpu_temp\": ${temp}}"
else
  echo "{}"
fi
