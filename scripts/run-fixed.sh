#!/usr/bin/env bash
# Milestone 04, steps 2-3: 15 load-test runs through the Ingress.
#   web replicas fixed at 1, 2, 3  x  rates 10, 25, 50, 100, 200 req/s, 60 s each
# During every run: kubectl top pods every 15 s; host CPU every 1 s throughout.
#   REPLICAS="1 2 3" RATES="10 25 50 100 200" SECONDS_PER_RUN=60 ./scripts/run-fixed.sh
source "$(dirname "$0")/lib.sh"
REPLICAS="${REPLICAS:-1 2 3}"
RATES="${RATES:-10 25 50 100 200}"
SECS="${SECONDS_PER_RUN:-60}"
OUT="$RESULTS/fixed"; mkdir -p "$OUT"

kubectl get hpa emi-web -n "$NS" >/dev/null 2>&1 && { warn "removing the HPA so replica counts stay fixed"; kubectl delete hpa emi-web -n "$NS"; }
minikube image ls -p "$PROFILE" | grep -q 'httperf:1.0' || die "httperf:1.0 not loaded; run ./scripts/build-loadgen.sh"

"$ROOT/scripts/host-cpu.sh" "$OUT/host_cpu.csv" & HOST=$!
trap 'kill $HOST ${TOP:-} 2>/dev/null || true' EXIT
[ -s "$OUT/runs.csv" ] || echo "replicas,rate,start_epoch,end_epoch,log" > "$OUT/runs.csv"

for r in $REPLICAS; do
  say "Scaling emi-web to $r replica(s)"
  kubectl scale deployment emi-web -n "$NS" --replicas="$r"
  kubectl -n "$NS" rollout status deployment/emi-web --timeout=180s
  sleep 20
  for rate in $RATES; do
    tag="${r}r_${rate}rps"
    say "Run $tag: $rate req/s for $SECS s with $r replica(s)   ($(now))"
    "$ROOT/scripts/pod-top.sh" "$OUT/pods_${tag}.csv" 15 & TOP=$!
    s=$(epoch)
    run_httperf_job "loadgen-$r-$rate" "$rate:$SECS" "$OUT/httperf_${tag}.log"
    e=$(epoch)
    sleep 15                                # one more sample after the load
    kill "$TOP" 2>/dev/null || true; TOP=""
    echo "$r,$rate,$s,$e,httperf_${tag}.log" >> "$OUT/runs.csv"
    grep -E 'Reply time|Reply status|Errors: total|Request rate' "$OUT/httperf_${tag}.log" | sed 's/^/      /' || true
    sleep 15                                # let CPU settle before the next run
  done
done
python3 "$ROOT/scripts/parse_results.py" fixed
ok "15 runs done; summary in results/fixed/summary.csv"
