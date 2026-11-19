#!/usr/bin/env bash
# Milestone 3, step 4b: delete the pod that is currently the MongoDB PRIMARY,
# show that a new PRIMARY is elected and that the app still saves calculations.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m3"; mkdir -p "$OUT"; LOG="$OUT/failover.txt"
check_ingress_reachable
primary_pod() {
  local p
  for p in mongo-0 mongo-1 mongo-2; do
    if kubectl -n "$NS" exec "$p" -- mongosh --quiet --eval 'print(db.hello().isWritablePrimary)' 2>/dev/null | grep -q true; then
      echo "$p"; return
    fi
  done
}
{
: > "$OUT/failover_watch.log"
watch_pods app=mongo "$OUT/failover_watch.log" & WATCH=$!
say "Before ($(now))"
"$ROOT/scripts/rs-status.sh"
"$ROOT/scripts/count-docs.sh" mongo-0
old=$(primary_pod); [ -n "$old" ] || die "no PRIMARY found"
echo "current PRIMARY pod: $old"

"$ROOT/scripts/request-loop.sh" "$OUT/failover_requests.log" 0.5 60 >/dev/null & LOOP=$!
sleep 5
say "kubectl delete pod $old -n emi   ($(now))"
t0=$(epoch)
kubectl -n "$NS" delete pod "$old" --wait=false
while :; do
  new=$(primary_pod)
  if [ -n "$new" ] && [ "$new" != "$old" ]; then break; fi
  sleep 1
done
echo "new PRIMARY: $new   elected about $(( $(epoch) - t0 )) s after the delete"
wait "$LOOP" || true
wait_pod_ready "$old"
sleep 10
kill "$WATCH" 2>/dev/null || true

say "After ($(now))"
"$ROOT/scripts/rs-status.sh"
"$ROOT/scripts/count-docs.sh" mongo-0
say "kubectl get pods -n emi -w (timestamped)"
cat "$OUT/failover_watch.log"
say "Requests through the Ingress during the failover"
cat "$OUT/failover_requests.log.summary"
} 2>&1 | tee "$LOG"
