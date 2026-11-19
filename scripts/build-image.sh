#!/usr/bin/env bash
# Build emi-web:<version> with the host's Docker and load it into Minikube.
#   ./scripts/build-image.sh 1.0      (default)
#   ./scripts/build-image.sh 1.1      (rolling-update version: new title/footer)
source "$(dirname "$0")/lib.sh"
V="${1:-1.0}"
need docker; need minikube

say "Building emi-web:$V"
docker build --build-arg APP_VERSION="$V" -t "emi-web:$V" "$ROOT/app"
docker image ls "emi-web:$V"

if minikube status -p "$PROFILE" >/dev/null 2>&1; then
  say "Loading emi-web:$V into Minikube (profile $PROFILE)"
  minikube image load "emi-web:$V" -p "$PROFILE" --overwrite=true
  minikube image ls -p "$PROFILE" | grep "emi-web:$V" && ok "emi-web:$V is available inside the cluster"
else
  warn "Minikube profile '$PROFILE' is not running; image built on the host only (fine for the local test)"
fi
