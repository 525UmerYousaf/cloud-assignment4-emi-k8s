#!/usr/bin/env bash
# Build the httperf image (compiled from source) and load it into Minikube.
source "$(dirname "$0")/lib.sh"
need docker; need minikube
say "Building httperf:1.0 (compiles httperf; takes a few minutes the first time)"
docker build -t httperf:1.0 "$ROOT/scripts/loadgen"
minikube image load httperf:1.0 -p "$PROFILE" --overwrite=true
minikube image ls -p "$PROFILE" | grep 'httperf:1.0' && ok "httperf:1.0 is available inside the cluster"
