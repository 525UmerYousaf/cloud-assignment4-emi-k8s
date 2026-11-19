#!/usr/bin/env bash
# Milestone 2 prerequisite: a fresh Minikube cluster for this assignment.
# Uses its own profile ("emi") so the Assignment 3 cluster is left untouched.
#   CPUS=4 MEMORY=6144 ./scripts/setup-cluster.sh
source "$(dirname "$0")/lib.sh"
CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-6144}"

need docker; need minikube; need kubectl
docker info >/dev/null 2>&1 || die "Docker is not running. Start Colima (colima start) or Docker Desktop first."

# Free CPU/RAM and port 80 if the Assignment 3 cluster is still running.
if minikube status -p minikube >/dev/null 2>&1; then
  warn "the Assignment 3 cluster (profile 'minikube') is running; stopping it"
  minikube stop -p minikube
fi

say "Starting Minikube profile '$PROFILE' (docker driver, ${CPUS} CPUs, ${MEMORY} MB)"
minikube start -p "$PROFILE" --driver=docker --cpus="$CPUS" --memory="$MEMORY"
minikube profile "$PROFILE"          # make it the default for minikube and kubectl
ok "cluster started; kubectl context is now '$(kubectl config current-context)'"

say "Enabling addons: metrics-server (for kubectl top / HPA) and ingress (NGINX)"
minikube addons enable metrics-server -p "$PROFILE"
minikube addons enable ingress -p "$PROFILE"

say "Tightening the metrics-server scrape interval to 15 s"
if ! kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q 'metric-resolution=15s'; then
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--metric-resolution=15s"}]'
fi
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

say "Waiting for the NGINX Ingress controller"
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s
ok "ingress controller ready"

say "Validating the cluster"
kubectl get nodes -o wide
kubectl get storageclass
for i in $(seq 1 24); do
  kubectl top nodes >/dev/null 2>&1 && break
  sleep 5
done
kubectl top nodes || warn "metrics not ready yet; give it another minute"
ok "cluster ready. Next: ./scripts/build-image.sh 1.0"
