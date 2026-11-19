#!/usr/bin/env bash
# rs.status() trimmed to member names and states.
source "$(dirname "$0")/lib.sh"
kubectl -n "$NS" exec mongo-0 -- mongosh --quiet --eval '
  const s = rs.status();
  print("set: " + s.set + "   date: " + s.date.toISOString());
  s.members.forEach(m => print("  " + m.name.padEnd(22) + m.stateStr.padEnd(11) + "health=" + m.health));'
