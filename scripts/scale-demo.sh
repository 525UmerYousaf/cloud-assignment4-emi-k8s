#!/usr/bin/env bash
# Milestone 3, step 3: scale 3 -> 5 and show that a new pod receives traffic
# only after it becomes Ready. Then repeat the 30-request distribution.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m3"; mkdir -p "$OUT"
check_ingress_reachable
: > "$OUT/scale_pods_watch.log"
watch_pods app=emi-web "$OUT/scale_pods_watch.log" & WATCH=$!
sleep 2
before=$(kubectl -n "$NS" get pods -l app=emi-web -o jsonpath='{.items[*].metadata.name}')

say "kubectl scale deployment emi-web --replicas=5 -n emi   ($(date '+%H:%M:%S'))"
kubectl scale deployment emi-web --replicas=5 -n "$NS"
"$ROOT/scripts/request-loop.sh" "$OUT/scale_requests.log" 0.2 30 >/dev/null
kubectl -n "$NS" rollout status deployment/emi-web --timeout=120s
kill "$WATCH" 2>/dev/null || true

say "New pods: when they became Ready vs. when they served their first request"
printf '%-32s %-10s %-10s %s\n' POD READY_AT FIRST_REQ VERDICT | tee "$OUT/scale_ready_vs_first.txt"
for p in $(kubectl -n "$NS" get pods -l app=emi-web -o jsonpath='{.items[*].metadata.name}'); do
  case " $before " in *" $p "*) continue ;; esac
  ready_utc=$(kubectl -n "$NS" get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}')
  # convert the UTC timestamp to local HH:MM:SS (BSD date on macOS, GNU date on Linux)
  ready=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ready_utc" '+%s' 2>/dev/null || date -u -d "$ready_utc" '+%s')
  ready_l=$(date -r "$ready" '+%H:%M:%S' 2>/dev/null || date -d "@$ready" '+%H:%M:%S')
  first=$(grep " $p " "$OUT/scale_requests.log" | head -n 1 | awk '{print $1}')
  verdict="no requests yet"
  [ -n "$first" ] && { [[ "$first" > "$ready_l" || "$first" == "$ready_l" ]] && verdict="first request after Ready" || verdict="CHECK: before Ready"; }
  printf '%-32s %-10s %-10s %s\n' "$p" "$ready_l" "${first:--}" "$verdict" | tee -a "$OUT/scale_ready_vs_first.txt"
done

say "Distribution with 5 replicas"
"$ROOT/scripts/spread.sh" 30 5r
