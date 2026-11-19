#!/usr/bin/env bash
# Milestone 04, step 4: HPA test, 10 minutes through the Ingress:
#   2 min at 10 req/s, 5 min at 100 req/s, 3 min at 10 req/s.
# Records the HPA every 15 s, pods every 15 s and host CPU every second.
#   PHASES="10:120 100:300 10:180" ./scripts/run-autoscale.sh
source "$(dirname "$0")/lib.sh"
PHASES="${PHASES:-10:120 100:300 10:180}"
OUT="$RESULTS/autoscale"; mkdir -p "$OUT"
minikube image ls -p "$PROFILE" | grep -q 'httperf:1.0' || die "httperf:1.0 not loaded; run ./scripts/build-loadgen.sh"

say "Applying the HPA (min 1, max 5, 50% CPU) and starting from 1 replica"
kubectl apply -f "$ROOT/k8s/autoscale/hpa.yaml"
kubectl scale deployment emi-web -n "$NS" --replicas=1
kubectl -n "$NS" rollout status deployment/emi-web --timeout=180s
for i in $(seq 1 24); do
  v=$(kubectl get hpa emi-web -n "$NS" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
  [ -n "$v" ] && break; sleep 5
done
kubectl get hpa emi-web -n "$NS"

rm -f "$OUT"/hpa.csv "$OUT"/hpa_raw.log "$OUT"/pods.csv "$OUT"/host_cpu.csv
"$ROOT/scripts/hpa-watch.sh" "$OUT" 15 & HPA=$!
"$ROOT/scripts/pod-top.sh" "$OUT/pods.csv" 15 & TOP=$!
"$ROOT/scripts/host-cpu.sh" "$OUT/host_cpu.csv" & HOST=$!
trap 'kill $HPA $TOP $HOST 2>/dev/null || true' EXIT
sleep 15

say "Load phases: $PHASES   (start $(now)); watch it live with: kubectl get hpa emi-web -n emi -w"
run_httperf_job loadgen-autoscale "$PHASES" "$OUT/httperf_autoscale.log"
say "Load finished ($(now)); recording 60 s more"
sleep 60
kill $HPA $TOP $HOST 2>/dev/null || true
kubectl describe hpa emi-web -n "$NS" | tee "$OUT/hpa_describe.txt" | tail -n 20
python3 "$ROOT/scripts/parse_results.py" autoscale
ok "autoscaling test done; raw data in results/autoscale/"
