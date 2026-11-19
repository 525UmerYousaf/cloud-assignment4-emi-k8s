#!/usr/bin/env bash
# Milestone 3, steps 2-3: send N POST /api/emi through the Ingress and count
# how many each pod served.
#   ./scripts/spread.sh 30 3r      -> results/m3/spread_3r.log
source "$(dirname "$0")/lib.sh"
N="${1:-30}"; LABEL="${2:-run}"
OUT="$RESULTS/m3"; mkdir -p "$OUT"; LOG="$OUT/spread_${LABEL}.log"
check_ingress_reachable
say "Sending $N requests to $APP_URL/api/emi"
: > "$LOG"
for i in $(seq 1 "$N"); do
  set -- $(post_emi)
  printf '%s  #%02d  http=%s  servedBy=%s\n' "$(date '+%H:%M:%S')" "$i" "$1" "$2" | tee -a "$LOG"
done
say "Requests served per pod ($LABEL)"
{
  echo "pod,requests"
  awk '{ sub("servedBy=", "", $4); print $4 }' "$LOG" | sort | uniq -c | awk '{ printf "%s,%s\n", $2, $1 }'
} | tee "$OUT/spread_${LABEL}.csv" | awk -F, '{ printf "  %-34s %s\n", $1, $2 }'
fails=$(grep -vc 'http=200' "$LOG" || true)
echo "failed requests: $fails"
