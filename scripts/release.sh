#!/usr/bin/env bash
# Builds Gander for release (issues #40, #41, #42): a Release archive, a DMG with the app and an Applications link, and,
# when you give it a Developer ID certificate and Apple credentials, a signed, notarized, stapled DMG.
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

echo "==> Making $dmg"
stage="$derived/dmg-stage"
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/Gander.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Gander $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
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
