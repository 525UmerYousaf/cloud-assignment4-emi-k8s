#!/usr/bin/env bash
# Milestone 2 deliverables, printed and saved under results/m2/.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m2"; mkdir -p "$OUT"
say "kubectl get all,pvc,configmap -n emi -o wide"
kubectl get all,pvc,configmap -n "$NS" -o wide | tee "$OUT/get_all.txt"
say "rs.status() (members and states)"
"$ROOT/scripts/rs-status.sh" | tee "$OUT/rs_status.txt"
say "kubectl logs job/mongo-init -n emi"
kubectl logs job/mongo-init -n "$NS" | tee "$OUT/mongo_init_job.log"
say "Saved calculations"
"$ROOT/scripts/count-docs.sh" | tee "$OUT/documents.txt"
ok "saved in results/m2/"
