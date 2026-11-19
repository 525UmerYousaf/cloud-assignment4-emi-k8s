# Shared helpers, sourced by the other scripts. Written for the bash 3.2 that
# ships with macOS (no associative arrays, no mapfile).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="emi"
PROFILE="${PROFILE:-emi}"            # Minikube profile used for this assignment
RESULTS="$ROOT/results"
APP_URL="${APP_URL:-http://emi.local}"
mkdir -p "$RESULTS"

if [ -t 1 ]; then C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_N=$'\033[0m'; else C_B=""; C_G=""; C_Y=""; C_R=""; C_N=""; fi
say()  { printf '%s==> %s%s\n' "$C_B" "$*" "$C_N"; }
ok()   { printf '%s    OK  %s%s\n' "$C_G" "$*" "$C_N"; }
warn() { printf '%s    !!  %s%s\n' "$C_Y" "$*" "$C_N"; }
die()  { printf '%s    XX  %s%s\n' "$C_R" "$*" "$C_N" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH"; }

now()   { date '+%Y-%m-%d %H:%M:%S'; }
epoch() { date '+%s'; }

# Random but valid loan inputs, as JSON.
rand_body() {
  local p r m
  p=$(( (RANDOM % 9950 + 50) * 100 ))                  # 5,000 .. 999,900
  r=$(printf '%d.%02d' $(( RANDOM % 18 + 3 )) $(( RANDOM % 100 )))  # 3.00 .. 20.99 %
  m=$(( RANDOM % 355 + 6 ))                            # 6 .. 360 months
  printf '{"principal":%s,"rate":%s,"months":%s}' "$p" "$r" "$m"
}

# One POST /api/emi through the Ingress. Prints: "<http_code> <pod> <version>"
post_emi() {
  local out code body pod ver
  out=$(curl -s --max-time 10 -X POST -H 'Content-Type: application/json' \
        -d "$(rand_body)" -w $'\n%{http_code}' "$APP_URL/api/emi" 2>/dev/null) || out=$'\n000'
  code=$(printf '%s' "$out" | tail -n 1)
  body=$(printf '%s' "$out" | sed '$d')
  pod=$(printf '%s' "$body" | sed -n 's/.*"servedBy":"\([^"]*\)".*/\1/p')
  ver=$(printf '%s' "$body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  printf '%s %s %s\n' "$code" "${pod:--}" "${ver:--}"
}

check_ingress_reachable() {
  local code
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$APP_URL/health" || true)
  [ "$code" = "200" ] || die "$APP_URL/health returned '$code'. Is 'minikube tunnel' running and emi.local in /etc/hosts?"
}

# Wait until a (possibly re-created) pod exists and is Ready.
wait_pod_ready() {
  local pod="$1" t=0
  until kubectl -n "$NS" wait --for=condition=ready "pod/$pod" --timeout=10s >/dev/null 2>&1; do
    sleep 2; t=$(( t + 12 ))
    [ "$t" -lt 360 ] || die "pod $pod did not become Ready"
  done
}

ingress_cluster_ip() {
  kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}'
}

# Watch pods with a timestamp on every line (kubectl -w has none).
# Usage: watch_pods <selector> <logfile> &   -> remember $! and kill it later
watch_pods() {
  kubectl get pods -n "$NS" -l "$1" -o wide -w 2>&1 | while IFS= read -r line; do
    printf '%s  %s\n' "$(date '+%H:%M:%S')" "$line"
  done >> "$2"
}

# Runs httperf as a Job inside the cluster, aimed at http://emi.local/ through
# the NGINX Ingress controller (emi.local is mapped to the controller's
# ClusterIP with hostAliases, so every request goes Ingress -> Service -> pod).
#   run_httperf_job <job-name> "<rate>:<seconds> [<rate>:<seconds> ...]" <logfile>
# Each request is POST /api/emi with random valid inputs (form-encoded),
# drawn from 1000 random session templates (httperf's maximum).
run_httperf_job() {
  local name="$1" phases="$2" log="$3" ip deadline=60 p r s
  ip=$(ingress_cluster_ip)
  [ -n "$ip" ] || die "ingress-nginx-controller Service not found; run scripts/setup-cluster.sh"
  for p in $phases; do r=${p%%:*}; s=${p##*:}; deadline=$(( deadline + s + 30 )); done
  kubectl delete job "$name" -n "$NS" --ignore-not-found --wait=true >/dev/null
  kubectl apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
  namespace: $NS
  labels: { app: loadgen }
spec:
  backoffLimit: 0
  activeDeadlineSeconds: $deadline
  template:
    metadata:
      labels: { app: loadgen }
    spec:
      restartPolicy: Never
      hostAliases:
        - ip: "$ip"
          hostnames: ["emi.local"]
      containers:
        - name: httperf
          image: httperf:1.0
          imagePullPolicy: Never
          resources:
            requests: { cpu: 250m, memory: 64Mi }
          command: ["bash", "-c"]
          args:
            - |
              set -u
              awk 'BEGIN { srand();
                for (i = 0; i < 1000; i++) {
                  p = (int(rand() * 9950) + 50) * 100;
                  r = 3 + int(rand() * 1800) / 100;
                  m = 6 + int(rand() * 355);
                  printf "/api/emi method=POST contents=principal=%d&rate=%.2f&months=%d\n\n", p, r, m } }' > /tmp/sessions.txt
              for phase in $phases; do
                rate=\${phase%%:*}; secs=\${phase##*:}; n=\$(( rate * secs ))
                echo "=== PHASE rate=\$rate seconds=\$secs sessions=\$n start=\$(date +%s)"
                httperf --hog --server=emi.local --port=80 --timeout=10 \\
                  --add-header='Content-Type: application/x-www-form-urlencoded\n' \\
                  --wsesslog=\$n,0,/tmp/sessions.txt --rate=\$rate
                echo "=== END rate=\$rate end=\$(date +%s)"
              done
EOF
  # wait for the pod to finish (Complete or Failed), then keep its log
  local t=0
  while :; do
    if kubectl get job "$name" -n "$NS" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null | grep -Eq 'Complete|Failed'; then break; fi
    sleep 5; t=$(( t + 5 ))
    [ "$t" -le $(( deadline + 60 )) ] || { warn "job $name did not finish in time"; break; }
  done
  kubectl logs "job/$name" -n "$NS" > "$log" 2>&1 || warn "could not read logs of job $name"
  kubectl delete job "$name" -n "$NS" --wait=false >/dev/null 2>&1 || true
}
