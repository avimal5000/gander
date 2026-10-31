#!/bin/bash
# Diagnostics for sleep/wake problems (M7). Captures, across a sleep/wake:
#   - Gander's own info-level log (macOS does not persist it, so it is streamed live),
#   - hang ("spin") reports from spindump and powerd's sleep-acknowledgement delays,
#   - per-second state and CPU of each Gander process (~100% = busy loop, ~0% = blocked),
#   - a 3 s stack sample of every thread whenever spindump flags Gander as hung.
# Usage: scripts/sleep-diag.sh [seconds, default 1800]. No admin rights needed.
# Output: $SWAY_DIAG_DIR, or $TMPDIR/sway-sleep-diag.
OUT="${SWAY_DIAG_DIR:-${TMPDIR:-/tmp}/sway-sleep-diag}"
DURATION="${1:-1800}"
mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/sample-*.txt

/usr/bin/log stream --level info --style compact --predicate \
  'subsystem == "com.avimal5000.sway"
   OR (process == "spindump" AND eventMessage CONTAINS "Gander")
   OR (process == "Gander" AND (messageType == error OR messageType == fault) AND NOT eventMessage CONTAINS "PullInput")
   OR (process == "powerd" AND eventMessage CONTAINS[c] "Gander")' \
  > "$OUT/stream.log" 2>&1 &
STREAM_PID=$!

# One line per second: time, pid, state, %cpu of each Gander process (state R/S, CPU ~100 = busy loop, ~0 = blocked).
(
  while true; do
    ps -axo pid=,stat=,%cpu=,comm= | awk -v t="$(date +%H:%M:%S)" '$4 ~ /\/Gander$/ || $4 == "Gander" { print t, $1, $2, $3 }'
    sleep 1
  done
) > "$OUT/cpu.log" 2>&1 &
CPU_PID=$!

# Sample every thread when spindump reports a spin (hang) for a Gander process; at most once per 20 s.
(
  last=0
  tail -n0 -F "$OUT/stream.log" 2>/dev/null | while read -r line; do
    case "$line" in
      *spindump*Gander*\[*\]*spin*)
        now=$(date +%s)
        if (( now - last >= 20 )); then
          last=$now
          pid=$(echo "$line" | sed -nE 's/.*Gander \[([0-9]+)\].*/\1/p')
          [ -n "$pid" ] && /usr/bin/sample "$pid" 3 -mayDie -file "$OUT/sample-$(date +%H%M%S)-$pid.txt" >/dev/null 2>&1 &
        fi
        ;;
    esac
  done
) &
WATCH_PID=$!

echo "sleep-diag running for ${DURATION}s; output in $OUT"
sleep "$DURATION"
kill "$STREAM_PID" "$CPU_PID" "$WATCH_PID" 2>/dev/null
pkill -P "$WATCH_PID" 2>/dev/null; pkill -f "tail -n0 -F $OUT/stream.log" 2>/dev/null
echo "sleep-diag finished"
