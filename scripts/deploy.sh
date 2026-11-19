#!/usr/bin/env bash
# Milestone 2: apply every manifest in k8s/ and wait until the system is up.
source "$(dirname "$0")/lib.sh"
need kubectl

say "kubectl apply -f k8s/"
kubectl apply -f "$ROOT/k8s/"

say "Waiting for the MongoDB StatefulSet (mongo-0, mongo-1, mongo-2)"
kubectl -n "$NS" rollout status statefulset/mongo --timeout=600s

say "Waiting for the mongo-init Job (rs.initiate)"
kubectl -n "$NS" wait --for=condition=complete job/mongo-init --timeout=600s
kubectl -n "$NS" logs job/mongo-init

say "Waiting for the web Deployment"
kubectl -n "$NS" rollout status deployment/emi-web --timeout=300s

kubectl get all,pvc,configmap,ingress -n "$NS" -o wide
ok "system is up"
