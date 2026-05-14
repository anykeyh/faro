#!/bin/sh
# Network probe for Faro.
#
# Returns JSON: per-interface throughput and errors.
#   eth0_rx_bytes, eth0_tx_bytes, eth0_rx_errors, eth0_tx_errors
# Also TCP connection stats.

set -eo pipefail

interfaces=$(tail -n +3 /proc/net/dev | awk -F: '{print $1}' | tr -d ' ')

first=true
echo -n "{"

for iface in $interfaces; do
  # Read stats from /proc/net/dev for this interface
  set -- $(awk -v iface="$iface" '$1 ~ iface":" {print $2, $3, $4, $5, $10, $11, $12, $13}' /proc/net/dev)
  rx_bytes=$1 rx_packets=$2 rx_err=$3 rx_drop=$4
  tx_bytes=$5 tx_packets=$6 tx_err=$7 tx_drop=$8

  [ "$first" = true ] && first=false || echo -n ","
  echo -n "\"${iface}_rx_bytes\": ${rx_bytes}"
  echo -n ", \"${iface}_tx_bytes\": ${tx_bytes}"
  echo -n ", \"${iface}_rx_errors\": ${rx_err}"
  echo -n ", \"${iface}_tx_errors\": ${tx_err}"
done

# TCP connection counts
tcp_established=$(ss -t state established 2>/dev/null | tail -n +2 | wc -l)
tcp_time_wait=$(ss -t state time-wait 2>/dev/null | tail -n +2 | wc -l)
tcp_retrans=$(nstat -a 2>/dev/null | awk '/TcpRetransSegs/ {print $2}')

echo -n ", \"tcp_established\": ${tcp_established:-0}"
echo -n ", \"tcp_time_wait\": ${tcp_time_wait:-0}"
echo -n ", \"tcp_retrans_segs\": ${tcp_retrans:-0}"

echo "}"
