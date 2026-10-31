#!/usr/bin/env bash
# Privacy audit (issue #38; PLAN.md sections 1 and 4): checks that Gander has no network access, writes no video or
# images, and uses the camera only while tracking. Run it after a build; add --runtime while Gander is running.
#
#   scripts/audit-privacy.sh [--app <path to Gander.app>] [--runtime [seconds]]
#
# Static checks (always): source guard, entitlements, Info.plist, and the built binary's linked libraries,
# undefined symbols, and embedded URLs.
# Runtime checks (--runtime): open sockets and written files of the running Gander process, and the camera
# start/stop lines in its log. They sample for `seconds` (default 20); toggle Tracking while they run.
set -uo pipefail
cd "$(dirname "$0")/.."

app=".build-xcode/Build/Products/Debug/Gander.app"
runtime=false
seconds=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) app="$2"; shift 2 ;;
    --runtime)
      runtime=true; shift
      if [[ ${1:-} =~ ^[0-9]+$ ]]; then seconds="$1"; shift; fi ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

failures=0
pass() { echo "  pass: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }
note() { echo "  note: $1"; }

echo "1. Source guard"
if scripts/privacy-guard.sh >/dev/null 2>&1; then pass "no networking, image persistence, input events or private APIs in shipped sources"
else fail "scripts/privacy-guard.sh reports forbidden APIs"; fi

echo "2. Entitlements and Info.plist"
keys=$(plutil -convert xml1 -o - Config/Gander.entitlements | grep -o "<key>[^<]*</key>" | sed 's/<[^>]*>//g' | sort)
if [[ "$keys" == "com.apple.security.device.camera" ]]; then pass "the only entitlement is the camera"
else fail "unexpected entitlements: $(echo "$keys" | tr '\n' ' ')"; fi
if grep -q 'INFOPLIST_KEY_NSCameraUsageDescription' Gander.xcodeproj/project.pbxproj; then pass "camera usage description present"
else fail "no camera usage description"; fi
if grep -q 'INFOPLIST_KEY_LSUIElement = YES' Gander.xcodeproj/project.pbxproj; then pass "menu bar app (LSUIElement)"
else fail "LSUIElement is not set"; fi

echo "3. Built binary ($app)"
if [[ ! -d "$app" ]]; then
  fail "no app at $app (build first, or pass --app)"
else
  # A Debug build keeps the code in Gander.debug.dylib beside a small stub executable; check every Mach-O inside.
  binaries=("$app/Contents/MacOS/"*)
  forbidden_libs='CFNetwork|WebKit|SystemConfiguration|NetworkExtension|libnetwork|/Network\.framework|Sparkle'
  net_symbols='_socket$|_connect$|_getaddrinfo$|_CFNetwork|NSURLSession|CFHTTP|_nw_connection|_nw_listener|_SCNetworkReachab|NSURLConnection'
  for binary in "${binaries[@]}"; do
    [[ -f "$binary" ]] || continue
    name=$(basename "$binary")
    if otool -L "$binary" 2>/dev/null | tail -n +2 | grep -qE "$forbidden_libs"; then fail "$name links a networking library"
    else pass "$name links no networking library"; fi
    if nm -u "$binary" 2>/dev/null | grep -qE "$net_symbols"; then fail "$name imports a networking symbol"
    else pass "$name imports no networking symbol"; fi
    urls=$(strings -a "$binary" | grep -oE "https?://[A-Za-z0-9./_?=&%-]+" | sort -u | tr '\n' ' ')
    if [[ -n "$urls" ]]; then note "$name embeds URL text (check it is not contacted): $urls"
    else pass "$name embeds no URLs"; fi
  done
  if codesign -d --entitlements - "$app" 2>/dev/null | grep -qE "network\.(client|server)"; then fail "the signed app has a network entitlement"
  else pass "the signed app has no network entitlement"; fi
fi

if $runtime; then
  echo "4. Running process (${seconds} s; toggle Tracking now)"
  pid=$(pgrep -x Gander | head -1 || true)
  if [[ -z "$pid" ]]; then
    fail "Gander is not running"
  else
    note "Gander pid $pid"
    marker=$(date "+%Y-%m-%d %H:%M:%S")
    sockets=""
    written=""
    end=$((SECONDS + seconds))
    while ((SECONDS < end)); do
      sockets+=$(lsof -nP -a -p "$pid" -i 2>/dev/null | tail -n +2)
      written+=$'\n'$(lsof -nP -a -p "$pid" -Fan 2>/dev/null | awk '/^a[wu]/{w=1; next} /^a/{w=0; next} /^n/{if(w) print substr($0,2)}')
      sleep 1
    done
    if [[ -z "${sockets//[$' \n\t']/}" ]]; then pass "no network sockets open"
    else fail "network sockets open:"; echo "$sockets" >&2; fi
    media=$(echo "$written" | grep -iE "\.(jpe?g|png|heic|tiff?|gif|mov|mp4|m4v|avi|raw|bmp)$" | sort -u)
    if [[ -z "$media" ]]; then pass "no image or video file open for writing"
    else fail "image or video files open for writing:"; echo "$media" >&2; fi
    echo "  files held open for writing (for review):"
    echo "$written" | sed '/^$/d' | sort -u | grep -vE "^/dev/(null|tty)" | sed 's/^/    /'
    echo "  camera lines in Gander's log since $marker (should match your Tracking toggles):"
    log show --info --start "$marker" --style compact \
      --predicate "subsystem == \"com.avimal5000.gander\" AND process == \"Gander\" AND (eventMessage CONTAINS \"Status:\" OR eventMessage CONTAINS \"Suspending\" OR eventMessage CONTAINS \"Resuming\")" 2>/dev/null |
      grep -vE "^Timestamp|^Filtering" | sed 's/^/    /' | tail -12
  fi
fi

echo
if ((failures == 0)); then echo "Privacy audit passed."; else echo "Privacy audit FAILED: $failures check(s)." >&2; exit 1; fi
