#!/usr/bin/env bash
# Network probe for Faro.
#
# Returns JSON: per-interface throughput and errors.
#   eth0_rx_bytes, eth0_tx_bytes, eth0_rx_errors, eth0_tx_errors
# Also TCP connection stats: tcp_established, tcp_time_wait, tcp_retrans

set -eo pipefail

# Per-interface stats from /proc/net/dev
interfaces=$(tail -n +3 /proc/net/dev | awk -F: '{print $1}' | tr -d ' ')
first=true
echo -n "{"

for iface in $interfaces; do
  stats=$(awk -v iface="$iface" '$1 ~ iface":" {print $2, $3, $10, $11}' /proc/net/dev)
  read -r rx_bytes rx_packets tx_errors tx_dropped <<< "$stats"
  read -r dummy tx_bytes tx_packets rx_errors rx_dropped <<< "$(awk -v iface="$iface" '$1 ~ iface":" {print $2, $3, $10, $11, $12, $13}' /proc/net/dev)"

  # Re-read properly
  set -- $(awk -v iface="$iface" '$1 ~ iface":" {print $2, $3, $4, $5, $10, $11, $12, $13}' /proc/net/dev)
  rx_bytes=$1; rx_packets=$2; rx_err=$3; rx_drop=$4
  tx_bytes=$5; tx_packets=$6; tx_err=$7; tx_drop=$8

  [ "$first" = true ] && first=false || echo -n ","
  echo -n "\"${iface}_rx_bytes\": ${rx_bytes}"
  echo -n ", \"${iface}_tx_bytes\": ${tx_bytes}"
  echo -n ", \"${iface}_rx_errors\": ${rx_err}"
  echo -n ", \"${iface}_tx_errors\": ${tx_err}"
done

# TCP connection counts from /proc/net/tcp
tcp_established=$(ss -t state established 2>/dev/null | tail -n +2 | wc -l || echo 0)
tcp_time_wait=$(ss -t state time-wait 2>/dev/null | tail -n +2 | wc -l || echo 0)
tcp_retrans=$(nstat -a 2>/dev/null | awk '/TcpRetransSegs/ {print $2}' || echo 0)

echo -n ", \"tcp_established\": ${tcp_established}"
echo -n ", \"tcp_time_wait\": ${tcp_time_wait}"
echo -n ", \"tcp_retrans_segs\": ${tcp_retrans:-0}"

echo "}"
