#!/usr/bin/env bash
# Milestone 3, step 4a: delete one web pod while requests keep flowing
# through the Ingress; the Deployment replaces it.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m3"; mkdir -p "$OUT"
check_ingress_reachable
: > "$OUT/selfheal_web_watch.log"
watch_pods app=emi-web "$OUT/selfheal_web_watch.log" & WATCH=$!
"$ROOT/scripts/request-loop.sh" "$OUT/selfheal_web_requests.log" 0.2 40 >/dev/null & LOOP=$!
sleep 8
victim=$(kubectl -n "$NS" get pods -l app=emi-web -o jsonpath='{.items[0].metadata.name}')
say "kubectl delete pod $victim -n emi   ($(date '+%H:%M:%S'))"
kubectl -n "$NS" delete pod "$victim" --wait=false
wait "$LOOP" || true
kubectl -n "$NS" rollout status deployment/emi-web --timeout=120s
kill "$WATCH" 2>/dev/null || true
say "kubectl get pods -n emi -w  (timestamped)"
cat "$OUT/selfheal_web_watch.log"
say "Request loop during the deletion"
cat "$OUT/selfheal_web_requests.log.summary"
