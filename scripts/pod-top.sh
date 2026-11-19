#!/usr/bin/env bash
# Per-pod CPU and memory from metrics-server, every 15 s (kubectl top pods),
# plus the Minikube node's own usage.
#   ./scripts/pod-top.sh results/x/pods.csv [interval]
# CSV: epoch,timestamp,pod,cpu_millicores,memory_mib
set -u
OUT="${1:-results/pods.csv}"; INTERVAL="${2:-15}"
mkdir -p "$(dirname "$OUT")"
[ -s "$OUT" ] || echo "epoch,timestamp,pod,cpu_millicores,memory_mib" > "$OUT"
while :; do
  e=$(date +%s); t=$(date '+%Y-%m-%d %H:%M:%S')
  kubectl top pods -n emi --no-headers 2>/dev/null | awk -v e="$e" -v t="$t" '{ gsub("m", "", $2); gsub("Mi", "", $3); print e "," t "," $1 "," $2 "," $3 }' >> "$OUT"
  kubectl top nodes --no-headers 2>/dev/null | awk -v e="$e" -v t="$t" '{ gsub("m", "", $2); gsub("Mi", "", $4); print e "," t ",node/" $1 "," $2 "," $4 }' >> "$OUT"
  sleep "$INTERVAL"
done
