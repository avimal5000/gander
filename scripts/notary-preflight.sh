#!/usr/bin/env bash
# Checks a built, signed Gander.app against what Apple's notary service and Gatekeeper reject, before spending a
# submission on it. Run by scripts/release.sh after signing; you can also run it by hand.
#
#   scripts/notary-preflight.sh <path to Gander.app> [--developer-id]
#
# Always checked: every Mach-O in the bundle is signed with the hardened runtime and holds both Apple silicon and Intel
# code; the signature verifies strictly; the entitlements are exactly the expected list (no debugging entitlement);
# Info.plist has the keys a release needs; the SDK and minimum macOS are recorded; nothing links a library from outside
# the system or the bundle; no symlink points outside the bundle.
# With --developer-id (a real certificate, not ad hoc): the signature is Developer ID Application, from team
# WNW4M84Z3U, with a secure timestamp. These three are what notarization adds on top, and an ad hoc build cannot
# have them.
set -uo pipefail

app="${1:-}"
developer_id=false
[[ "${2:-}" == "--developer-id" ]] && developer_id=true
if [[ -z "$app" || ! -d "$app" ]]; then
  echo "Usage: scripts/notary-preflight.sh <path to Gander.app> [--developer-id]" >&2
  exit 2
fi

team="WNW4M84Z3U"
expected_entitlements="com.apple.security.device.camera"
failures=0
pass() { echo "  pass: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

echo "Notary preflight: $app"

echo "1. Code in the bundle"
machos=()
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q "Mach-O" && machos+=("$f")
done < <(find "$app" -type f -print0)
if ((${#machos[@]} == 0)); then fail "no executable code found"; fi
for m in "${machos[@]}"; do
  rel="${m#"$app"/}"
  info=$(codesign -dvvv "$m" 2>&1)
  if [[ "$info" == *"code object is not signed"* ]]; then fail "$rel is not signed"; continue; fi
  if grep -qE "^CodeDirectory.*flags=0x[0-9a-f]*\(.*runtime" <<<"$info"; then pass "$rel uses the hardened runtime"
  else fail "$rel is signed without the hardened runtime (sign with --options runtime)"; fi
  archs=$(lipo -archs "$m" 2>/dev/null)
  if [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]]; then pass "$rel holds arm64 and x86_64"
  else fail "$rel holds only: $archs (build with ONLY_ACTIVE_ARCH=NO)"; fi
  # Library lines start with a tab; a universal binary also prints a "(architecture …):" header per slice.
  outside=$(otool -L "$m" 2>/dev/null | awk '/^\t/ {print $1}' | grep -vE "^(/System/|/usr/lib/|@rpath/|@executable_path/|@loader_path/)" | sort -u)
  if [[ -z "$outside" ]]; then pass "$rel links only system or bundled libraries"
  else fail "$rel links libraries outside the system and the bundle: $(tr '\n' ' ' <<<"$outside")"; fi
  sdk=$(vtool -show-build "$m" 2>/dev/null | awk '/ sdk /{print $2; exit}')
  if [[ -n "$sdk" ]]; then pass "$rel was built with the macOS $sdk SDK"
  else fail "$rel records no SDK version"; fi
done

echo "2. Signature"
if codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1; then pass "the signature verifies strictly"
else fail "codesign --verify --deep --strict fails:"; codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | sed 's/^/    /' >&2; fi
escaping=$(find "$app" -type l | while read -r l; do
  target=$(cd "$(dirname "$l")" && cd "$(dirname "$(readlink "$l")")" 2>/dev/null && pwd -P)
  [[ "$target" == "$(cd "$app" && pwd -P)"* ]] || echo "${l#"$app"/}"
done)
if [[ -z "$escaping" ]]; then pass "no symlink points outside the bundle"
else fail "symlinks point outside the bundle: $escaping"; fi

echo "3. Entitlements"
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null |
  grep -o "<key>[^<]*</key>" | sed 's/<[^>]*>//g' | sort | tr '\n' ' ' | sed 's/ $//')
if [[ "$entitlements" == "$expected_entitlements" ]]; then pass "entitlements are exactly: $expected_entitlements"
else fail "entitlements are '$entitlements', expected '$expected_entitlements'"; fi
if [[ "$entitlements" == *"get-task-allow"* ]]; then fail "com.apple.security.get-task-allow is set: notarization rejects debuggable builds"; fi

echo "4. Info.plist"
plist="$app/Contents/Info.plist"
for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion CFBundleExecutable LSMinimumSystemVersion NSCameraUsageDescription; do
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null)
  if [[ -n "$value" ]]; then pass "$key = $value"; else fail "$key is missing"; fi
done
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null)
[[ "$id" == "com.avimal5000.gander" ]] || fail "bundle identifier changed to '$id': macOS would treat it as a new app and drop the user's permissions"

echo "5. Developer ID"
if $developer_id; then
  details=$(codesign -dvvv "$app" 2>&1)
  if grep -q "^Authority=Developer ID Application:" <<<"$details"; then pass "signed with a Developer ID Application certificate"
  else fail "not signed with a Developer ID Application certificate"; fi
  if grep -q "^TeamIdentifier=$team$" <<<"$details"; then pass "team $team"
  else fail "team is $(grep '^TeamIdentifier=' <<<"$details" | cut -d= -f2), expected $team"; fi
  if grep -q "^Timestamp=" <<<"$details"; then pass "secure timestamp present"
  else fail "no secure timestamp (sign with --timestamp)"; fi
else
  echo "  skipped: ad hoc build (pass --developer-id to check the certificate, team and timestamp)"
fi

echo
if ((failures == 0)); then echo "Notary preflight passed."
else echo "Notary preflight FAILED: $failures check(s)." >&2; exit 1; fi
