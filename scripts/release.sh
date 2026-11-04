#!/usr/bin/env bash
# Builds Gander for release (issues #40, #41, #42): a Release archive, a DMG with the app, an Applications link and a
# branded window, and, when you give it a Developer ID certificate and Apple credentials, a signed, notarized, stapled
# DMG.
#
#   scripts/release.sh [--version 0.1.0] [--build-number 1] [--out dist]
#                      [--identity "Developer ID Application: Name (TEAMID)"]
#                      [--notarize]
#
# Without --identity the app is only ad-hoc signed: it runs on this Mac, but another Mac's Gatekeeper warns about
# it (see docs/RELEASING.md). Notarization reads these environment variables (never put them on a command line):
#   APPLE_ID                    your Apple ID email
#   APPLE_APP_SPECIFIC_PASSWORD an app-specific password from appleid.apple.com
#   APPLE_TEAM_ID               your 10-character team ID
set -euo pipefail
cd "$(dirname "$0")/.."

version=""
build_number=""
out="dist"
identity=""
notarize=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build-number) build_number="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --identity) identity="$2"; shift 2 ;;
    --notarize) notarize=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -z "$version" ]]; then
  version=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);/\1/p' Gander.xcodeproj/project.pbxproj | head -1)
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "The version must look like 0.1.0 (got '$version')." >&2
  exit 2
fi
build_number="${build_number:-1}"
if $notarize && [[ -z "$identity" ]]; then
  echo "--notarize needs --identity (notarization requires a Developer ID signature)." >&2
  exit 2
fi
if $notarize; then
  : "${APPLE_ID:?Set APPLE_ID}" "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}" "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
fi

derived=".build-release"
app="$derived/Build/Products/Release/Gander.app"
mkdir -p "$out"
dmg="$out/Gander-$version.dmg"

echo "==> Building Gander $version ($build_number), Release"
rm -rf "$derived"
# Signing is done afterwards, in one place, so the same steps serve a certificate and ad-hoc signing.
xcodebuild -project Gander.xcodeproj -scheme Gander -configuration Release -derivedDataPath "$derived" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=NO build | tail -5

[[ -d "$app" ]] || { echo "The build produced no app at $app." >&2; exit 1; }

echo "==> Signing ${identity:-ad hoc}"
sign_identity="${identity:--}"
sign_flags=(--force --options runtime --entitlements Config/Gander.entitlements)
[[ -n "$identity" ]] && sign_flags+=(--timestamp)
codesign "${sign_flags[@]}" --sign "$sign_identity" "$app"
codesign --verify --strict --verbose=2 "$app"

echo "==> Checking the app before packaging"
scripts/audit-privacy.sh --app "$app"

echo "==> Checking the deprecated Carbon calls are weak imports (SPEC D53)"
# A strong import of a call Apple has removed would stop Gander from launching at all.
carbon_imports=$(nm -m -arch all "$app/Contents/MacOS/Gander" | grep -E ' _(GetProcessForPID|SetFrontProcessWithOptions) ' || true)
if [[ -z "$carbon_imports" ]] || grep -qv 'weak external' <<<"$carbon_imports"; then
  echo "Expected only weak imports of GetProcessForPID and SetFrontProcessWithOptions, got:" >&2
  echo "${carbon_imports:-(none)}" >&2
  exit 1
fi

echo "==> Making $dmg"
# The window: a branded background with an arrow from Gander to Applications (scripts/make-dmg-background.swift),
# laid out by dmgbuild (scripts/dmg-settings.py), which writes Finder's layout file directly instead of driving Finder.
art="$derived/dmg-art"
background_flags=()
$notarize && background_flags+=(--notarized)
swift scripts/make-dmg-background.swift "$art" ${background_flags[@]+"${background_flags[@]}"}
tiffutil -cathidpicheck "$art/background.png" "$art/background@2x.png" -out "$art/background.tiff" >/dev/null 2>&1
venv="$derived/dmgbuild-venv"
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes -r scripts/dmg-requirements.txt
rm -f "$dmg"
# hdiutil prints a deprecation warning for each step; show dmgbuild's output only when it fails.
if ! dmgbuild_log=$("$venv/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$app" \
  -D background="$art/background.tiff" "Gander $version" "$dmg" 2>&1); then
  echo "$dmgbuild_log" >&2
  exit 1
fi
if [[ -n "$identity" ]]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
fi

if $notarize; then
  echo "==> Notarizing (this waits for Apple, usually a few minutes)"
  xcrun notarytool submit "$dmg" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

(cd "$out" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
hdiutil verify "$dmg" >/dev/null

echo
echo "Done: $dmg"
cat "$dmg.sha256"
if [[ -z "$identity" ]]; then
  echo "Signed ad hoc only: other Macs will warn. See docs/RELEASING.md to sign and notarize."
elif ! $notarize; then
  echo "Signed but not notarized: other Macs will still warn. Add --notarize."
fi
