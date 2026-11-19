#!/usr/bin/env bash
# Milestone 1: run the app and a single MongoDB container locally with Docker.
#   ./scripts/local-test.sh up     -> http://localhost:8080
#   ./scripts/local-test.sh down   -> remove the containers and network
source "$(dirname "$0")/lib.sh"
need docker
case "${1:-up}" in
  up)
    docker image inspect emi-web:1.0 >/dev/null 2>&1 || "$ROOT/scripts/build-image.sh" 1.0
    docker network inspect emi-local >/dev/null 2>&1 || docker network create emi-local >/dev/null
    docker rm -f emi-mongo emi-web-local >/dev/null 2>&1 || true
    say "Starting MongoDB (mongo:7.0) as emi-mongo"
    docker run -d --name emi-mongo --network emi-local mongo:7.0 >/dev/null
    say "Starting emi-web:1.0 on http://localhost:8080"
    docker run -d --name emi-web-local --hostname emi-web-local --network emi-local -p 8080:8080 \
      -e MONGO_URL="mongodb://emi-mongo:27017/emidb" emi-web:1.0 >/dev/null
    for i in $(seq 1 30); do
      [ "$(curl -s -o /dev/null -w '%{http_code}' localhost:8080/health)" = "200" ] && break
      sleep 2
    done
    curl -s localhost:8080/health; echo
    ok "open http://localhost:8080 in your browser"
    ;;
  down)
    docker rm -f emi-web-local emi-mongo >/dev/null 2>&1 || true
    docker network rm emi-local >/dev/null 2>&1 || true
    ok "local test containers removed"
    ;;
  *) die "usage: $0 up|down" ;;
esac
