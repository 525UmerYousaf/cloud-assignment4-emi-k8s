#!/usr/bin/env bash
# Records the HPA every 15 s: the raw "kubectl get hpa emi-web -n emi" line
# (hpa_raw.log) and the numbers as CSV.
#   ./scripts/hpa-watch.sh results/autoscale
# CSV: epoch,timestamp,current_replicas,desired_replicas,cpu_pct,target_pct
set -u
DIR="${1:-results/autoscale}"; INTERVAL="${2:-15}"
mkdir -p "$DIR"
CSV="$DIR/hpa.csv"; RAW="$DIR/hpa_raw.log"
[ -s "$CSV" ] || echo "epoch,timestamp,current_replicas,desired_replicas,cpu_pct,target_pct" > "$CSV"
while :; do
  e=$(date +%s); t=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$t  $(kubectl get hpa emi-web -n emi --no-headers 2>&1)" >> "$RAW"
  v=$(kubectl get hpa emi-web -n emi -o jsonpath='{.status.currentReplicas},{.status.desiredReplicas},{.status.currentMetrics[0].resource.current.averageUtilization},{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || echo ",,,")
  echo "$e,$t,$v" >> "$CSV"
  sleep "$INTERVAL"
done
