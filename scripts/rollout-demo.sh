#!/usr/bin/env bash
# Milestone 3, step 5: rolling update 1.0 -> 1.1 with a request loop running,
# then kubectl rollout undo back to 1.0. Needs emi-web:1.1 loaded first:
#   ./scripts/build-image.sh 1.1
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m3"; mkdir -p "$OUT"; LOG="$OUT/rollout.txt"
check_ingress_reachable
minikube image ls -p "$PROFILE" | grep -q 'emi-web:1.1' || die "emi-web:1.1 not in Minikube; run ./scripts/build-image.sh 1.1"
{
kubectl -n "$NS" annotate deployment emi-web kubernetes.io/change-cause="initial release emi-web:1.0" --overwrite >/dev/null
"$ROOT/scripts/request-loop.sh" "$OUT/rollout_requests.log" 0.2 0 >/dev/null & LOOP=$!
sleep 5

say "kubectl set image deployment/emi-web emi-web=emi-web:1.1 -n emi   ($(now))"
kubectl -n "$NS" set image deployment/emi-web emi-web=emi-web:1.1
kubectl -n "$NS" annotate deployment emi-web kubernetes.io/change-cause="update to emi-web:1.1 (new title/footer)" --overwrite >/dev/null
kubectl -n "$NS" rollout status deployment/emi-web --timeout=300s
sleep 10
say "kubectl rollout history deployment/emi-web -n emi"
kubectl -n "$NS" rollout history deployment/emi-web

printf '\n    >>> Open http://emi.local now: the title and footer show v1.1. Take the screenshot, then press Enter to roll back. ' > /dev/tty
read -r _ < /dev/tty
say "kubectl rollout undo deployment/emi-web -n emi   ($(now))"
kubectl -n "$NS" rollout undo deployment/emi-web
kubectl -n "$NS" rollout status deployment/emi-web --timeout=300s
sleep 10
kill -TERM "$LOOP" 2>/dev/null || true; wait "$LOOP" 2>/dev/null || true
say "kubectl rollout history (after undo)"
kubectl -n "$NS" rollout history deployment/emi-web
kubectl -n "$NS" get deployment emi-web -o jsonpath='image now: {.spec.template.spec.containers[0].image}{"\n"}'
say "Request loop: every request during both rollouts"
cat "$OUT/rollout_requests.log.summary"
} 2>&1 | tee "$LOG"
