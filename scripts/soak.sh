#!/usr/bin/env bash
# Soak test helper (issue #39): records Sway's CPU, memory, and threads while you use it all day, and Sway's own log
# lines (switches, camera events), then summarizes both.
#
#   scripts/soak.sh sample [out.csv] [interval seconds]   run until Ctrl-C (default .build-logs/soak-<date>.csv, 30 s)
#   scripts/soak.sh report <out.csv>                       summary of a finished or running sample
#
# Sampling only reads process statistics (`top`, `pmset`) and streams Sway's log; it never touches the camera or Sway
# itself. The log lines go to <out>.log next to the CSV, because macOS keeps info-level log lines only for a few
# minutes: reading them afterwards would miss most of a day. A pid change in the middle of a run means Sway quit or
# crashed, and the report says so.
set -uo pipefail
cd "$(dirname "$0")/.."

subsystem="com.avimal5000.sway"
bundle_id="com.avimal5000.sway"
# Only the app itself: the tests log under the same subsystem from their own processes.
predicate="subsystem == \"$subsystem\" AND process == \"Sway\""

sample() {
  local out="${1:-.build-logs/soak-$(date +%Y%m%d-%H%M).csv}"
  local interval="${2:-30}"
  mkdir -p "$(dirname "$out")"
  echo "time,pid,cpu_percent,rss_mb,threads,power" > "$out"
  local logfile="${out%.csv}.log"
  : > "$logfile"
  # The switching timing in force at the start, so a report can be compared with another run's.
  defaults export "$bundle_id" - 2>/dev/null | python3 -I -c '
import sys, plistlib, json
try:
    value = plistlib.loads(sys.stdin.buffer.read()).get("sway.switchSensitivity")
    print(json.dumps(json.loads(value)) if value else "defaults (hold 0.40 s, pause 0.75 s, confidence 2)")
except Exception:
    print("unknown")
' > "${out%.csv}.settings" 2>/dev/null || echo "unknown" > "${out%.csv}.settings"
  /usr/bin/log stream --style compact --level info --predicate "$predicate" >> "$logfile" 2>/dev/null &
  local stream_pid=$!
  trap 'kill "$stream_pid" 2>/dev/null; exit 0' INT TERM
  trap 'kill "$stream_pid" 2>/dev/null' EXIT
  echo "Sampling Sway every ${interval} s into $out and its log lines into $logfile (Ctrl-C to stop)."
  while true; do
    local pid
    pid=$(pgrep -x Sway | head -1 || true)
    if [[ -n "$pid" ]]; then
      # Two `top` samples one second apart: the second is the CPU over that second, not since launch.
      local line cpu rss threads power
      line=$(top -l 2 -s 1 -pid "$pid" -stats cpu,mem,th 2>/dev/null | tail -1)
      cpu=$(awk '{print $1}' <<<"$line")
      rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1f", $1/1024}')
      threads=$(awk '{print $3}' <<<"$line" | tr -d '/+')
      power=$(pmset -g batt | head -1 | grep -q "AC Power" && echo ac || echo battery)
      echo "$(date '+%Y-%m-%d %H:%M:%S'),$pid,${cpu:-0},${rss:-0},${threads:-0},$power" >> "$out"
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S'),0,0,0,0," >> "$out"
    fi
    sleep "$interval"
  done
}

report() {
  local csv="${1:?usage: soak.sh report <out.csv>}"
  [[ -f "$csv" ]] || { echo "No such file: $csv" >&2; exit 2; }
  local first last
  first=$(sed -n 2p "$csv" | cut -d, -f1)
  last=$(tail -1 "$csv" | cut -d, -f1)
  echo "Soak report: $csv"
  echo "From $first to $last"
  [[ -f "${csv%.csv}.settings" ]] && echo "Switching settings at the start: $(cat "${csv%.csv}.settings")"
  echo
  awk -F, '
    NR == 1 { next }
    $2 == 0 { gaps++; next }
    {
      n++; pid = $2
      if (prev && pid != prev) restarts++
      prev = pid
      c = $3 + 0; r = $4 + 0
      cpus[++k] = c; sumc += c; if (c > maxc) maxc = c
      byp[$6] += c; cnt[$6]++
      if (n == 1) { r0 = r; t0 = $1 }
      rl = r; if (r > maxr) maxr = r
      thr = $5
    }
    END {
      if (!n) { print "No samples with Sway running."; exit }
      # p95 of CPU by a simple insertion sort (a day is a few thousand samples at most).
      for (i = 2; i <= k; i++) { v = cpus[i]; j = i - 1; while (j > 0 && cpus[j] > v) { cpus[j+1] = cpus[j]; j-- } cpus[j+1] = v }
      p95 = cpus[int(k * 0.95) + (k * 0.95 > int(k * 0.95) ? 1 : 0)]
      printf "Samples with Sway running: %d (%d with Sway not running)\n", n, gaps
      printf "CPU of one core: mean %.1f%%, 95th percentile %.1f%%, max %.1f%%\n", sumc / n, p95, maxc
      for (p in cnt) printf "  on %s: mean %.1f%% over %d samples\n", (p == "" ? "unknown power" : p), byp[p] / cnt[p], cnt[p]
      printf "Memory: first %.1f MB, last %.1f MB, max %.1f MB (change %+.1f MB)\n", r0, rl, maxr, rl - r0
      printf "Threads at the end: %s\n", thr
      if (restarts) printf "WARNING: Sway restarted %d time(s) during the run (quit or crash)\n", restarts
    }' "$csv"

  # Memory growth per hour from the first and last running samples.
  awk -F, 'NR > 1 && $2 != 0 { if (!t0) { t0 = $1; r0 = $4 } t1 = $1; r1 = $4 } END {
      if (!t0) exit
      cmd = "date -j -f \"%Y-%m-%d %H:%M:%S\" \"" t0 "\" +%s"; cmd | getline a; close(cmd)
      cmd = "date -j -f \"%Y-%m-%d %H:%M:%S\" \"" t1 "\" +%s"; cmd | getline b; close(cmd)
      h = (b - a) / 3600
      if (h > 0.25) printf "Memory trend: %+.1f MB per hour (a steady climb over hours is a leak; flat is fine)\n", (r1 - r0) / h
    }' "$csv"

  echo
  echo "From Sway's log in that period:"
  local events logfile="${csv%.csv}.log"
  if [[ -f "$logfile" ]]; then
    events=$(grep -vE "^Timestamp|^Filtering" "$logfile" || true)
  else
    echo "  (no $logfile: only the last few minutes of log lines are still stored, so the counts below are incomplete;"
    echo "   start a run with 'scripts/soak.sh sample' to capture them)"
    events=$(/usr/bin/log show --info --style compact --start "$first" --end "$last" \
      --predicate "$predicate" 2>/dev/null | grep -vE "^Timestamp|^Filtering" || true)
  fi
  count() { grep -cE "$1" <<<"$events" || true; }
  echo "  switches focused:        $(count 'Focused .* on .* via')"
  echo "  display had no window:   $(count 'No window on')"
  echo "  switches that failed:    $(count 'Switch to .* failed')"
  echo "  camera stalls:           $(count 'Camera stalled')"
  echo "  capture restarts:        $(count 'restarting the capture session')"
  echo "  interruptions ended:     $(count 'interruption ended')"
  echo "  suspended (sleep/lock):  $(count 'Suspending capture')"
  echo "  resumed:                 $(count 'Resuming capture')"
  echo "  camera unplugged/back:   $(count 'Camera disconnected') / $(count 'Camera reconnected')"
  echo "  pose source failures:    $(count 'Pose source failed')"

  local settings_seen
  settings_seen=$(grep -oE "Switching settings: .*" <<<"$events" | sort -u || true)
  if [[ -n "$settings_seen" ]]; then
    echo "  settings changed during the run:"
    sed 's/^/    /' <<<"$settings_seen"
  fi

  # Likely false switches: a switch to display B followed within 3 s by a switch back to display A.
  local reversals
  reversals=$(grep -E "Focused .* on .* via" <<<"$events" | awk '
    function secs(t,   p) { split(t, p, /[:.]/); return p[1]*3600 + p[2]*60 + p[3] + ("0." p[4]) }
    { t = secs($2); d = $0; sub(/.* on /, "", d); sub(/ via .*/, "", d)
      if (n && prevd != d && t - prevt <= 3 && d == prevprevd) rev++
      prevprevd = prevd; prevd = d; prevt = t; n++ }
    END { print rev + 0 }')
  echo "  quick reversals (A to B to A within 3 s, a likely false switch): $reversals"
  echo
  echo "Add your own notes: any switch you did not want, and the time it happened."
}

case "${1:-}" in
  sample) shift; sample "$@" ;;
  report) shift; report "$@" ;;
  *) echo "Usage: scripts/soak.sh sample [out.csv] [interval] | report <out.csv>" >&2; exit 2 ;;
esac
