#!/usr/bin/env bash
# Number of saved calculations, plus the newest three (read from the PRIMARY).
source "$(dirname "$0")/lib.sh"
POD="${1:-mongo-0}"
URL="$(kubectl -n "$NS" get configmap emi-config -o jsonpath='{.data.MONGO_URL}')"
kubectl -n "$NS" exec "$POD" -- mongosh --quiet "$URL" --eval '
  print("calculations: " + db.calculations.countDocuments());
  db.calculations.find({}, {_id: 0}).sort({createdAt: -1}).limit(3).forEach(d =>
    print("  " + d.createdAt.toISOString() + "  P=" + d.principal + " rate=" + d.rate + " n=" + d.months + " emi=" + d.emi + "  " + d.servedBy));'
