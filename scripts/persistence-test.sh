#!/usr/bin/env bash
# Milestone 2, step 8: delete mongo-1 and show that the StatefulSet brings it
# back with the same name and the same PVC, and that no data is lost.
source "$(dirname "$0")/lib.sh"
OUT="$RESULTS/m2/persistence_test.txt"; mkdir -p "$RESULTS/m2"
{
pod_facts() {
  kubectl -n "$NS" get pod mongo-1 -o jsonpath='pod={.metadata.name}  uid={.metadata.uid}  created={.metadata.creationTimestamp}  pvc={.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}{"\n"}'
}
say "BEFORE  ($(now))"
kubectl -n "$NS" get pods -l app=mongo -o wide
kubectl -n "$NS" get pvc
pod_facts
"$ROOT/scripts/count-docs.sh" mongo-0

say "kubectl delete pod mongo-1 -n emi   ($(now))"
kubectl -n "$NS" delete pod mongo-1
wait_pod_ready mongo-1
sleep 10   # let it rejoin the replica set

say "AFTER  ($(now))"
kubectl -n "$NS" get pods -l app=mongo -o wide
kubectl -n "$NS" get pvc
pod_facts
"$ROOT/scripts/count-docs.sh" mongo-0
say "Documents on mongo-1 itself (its own copy of the data, read from the PVC)"
kubectl -n "$NS" exec mongo-1 -- mongosh --quiet --eval 'db.getMongo().setReadPref("secondaryPreferred"); print("mongo-1 calculations: " + db.getSiblingDB("emidb").calculations.countDocuments())'
"$ROOT/scripts/rs-status.sh"
} 2>&1 | tee "$OUT"
ok "saved in results/m2/persistence_test.txt (same name, same PVC, new uid and age)"
