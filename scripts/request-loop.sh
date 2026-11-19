#!/usr/bin/env bash
# Continuous POST /api/emi through the Ingress, one line per request:
#   time  http_code  pod  version
# Stops after DURATION seconds (0 = until Ctrl-C) and prints a summary.
#   ./scripts/request-loop.sh results/m3/loop.log 0.2 0
source "$(dirname "$0")/lib.sh"
LOG="${1:-$RESULTS/m3/request_loop.log}"; GAP="${2:-0.2}"; DURATION="${3:-0}"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"; : > "$LOG.summary"
summary() {
  local total okc
  total=$(wc -l < "$LOG" | tr -d ' ')
  okc=$(grep -c ' 200 ' "$LOG" || true)
  {
    echo "---- summary ----"
    echo "requests: $total   ok (200): $okc   failed: $(( total - okc ))"
    echo "by version:"; awk '{ print "  version " $4 }' "$LOG" | sort | uniq -c
    echo "by pod:";     awk '{ print "  " $3 }' "$LOG" | sort | uniq -c
  } | tee "$LOG.summary"
}
# TERM is used when this runs in the background (background jobs ignore INT).
trap 'summary; exit 0' INT TERM
start=$(epoch)
while :; do
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$(post_emi)" >> "$LOG"
  tail -n 1 "$LOG"
  if [ "$DURATION" -gt 0 ] && [ $(( $(epoch) - start )) -ge "$DURATION" ]; then break; fi
  sleep "$GAP"
done
summary
