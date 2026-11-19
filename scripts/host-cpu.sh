#!/usr/bin/env bash
# Host CPU profiler: overall CPU of this machine once per second.
#   ./scripts/host-cpu.sh results/host_cpu.csv      (runs until killed)
# CSV: epoch,timestamp,cpu_pct
# macOS: iostat (built in); Linux: deltas of /proc/stat.
set -u
OUT="${1:-results/host_cpu.csv}"
mkdir -p "$(dirname "$OUT")"
[ -s "$OUT" ] || echo "epoch,timestamp,cpu_pct" > "$OUT"

if [ "$(uname)" = "Darwin" ]; then
  # Each call takes two samples one second apart and prints the second, so
  # every line is a fresh 1-second average (avoids pipe buffering of a
  # long-running iostat).
  while :; do
    idle=$(iostat -n 0 -c 2 -w 1 | tail -n 1 | awk '{ print $3 }')
    case "$idle" in ''|*[!0-9]*) continue ;; esac
    echo "$(date +%s),$(date '+%Y-%m-%d %H:%M:%S'),$(( 100 - idle ))" >> "$OUT"
  done
else
  read_cpu() { awk '/^cpu / { idle = $5 + $6; tot = 0; for (i = 2; i <= 9; i++) tot += $i; print tot, idle }' /proc/stat; }
  set -- $(read_cpu); pt=$1; pi=$2
  while sleep 1; do
    set -- $(read_cpu); t=$1; i=$2
    pct=$(awk -v dt=$(( t - pt )) -v di=$(( i - pi )) 'BEGIN { if (dt > 0) printf "%.1f", 100 * (dt - di) / dt; else print 0 }')
    echo "$(date +%s),$(date '+%Y-%m-%d %H:%M:%S'),$pct" >> "$OUT"
    pt=$t; pi=$i
  done
fi
