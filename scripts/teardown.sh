#!/usr/bin/env bash
# Remove the application (the MongoDB PVCs, i.e. the stored data, are kept
# unless --data is given) and stop the cluster.
#   ./scripts/teardown.sh            delete workloads, keep data, stop Minikube
#   ./scripts/teardown.sh --data     also delete the PVCs (all calculations)
#   ./scripts/teardown.sh --cluster  delete the whole Minikube profile
source "$(dirname "$0")/lib.sh"
case "${1:-}" in
  --cluster) minikube delete -p "$PROFILE"; ok "profile $PROFILE deleted"; exit 0 ;;
  --data)    kubectl delete namespace "$NS" --ignore-not-found; ok "namespace emi deleted (including PVCs)" ;;
  *)         kubectl delete -f "$ROOT/k8s/autoscale/" --ignore-not-found
             kubectl delete deployment,statefulset,job,service,ingress,configmap --all -n "$NS" --ignore-not-found
             ok "workloads deleted; PVCs (data) kept: kubectl get pvc -n emi" ;;
esac
minikube stop -p "$PROFILE"
