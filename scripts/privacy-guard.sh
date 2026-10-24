#!/usr/bin/env bash
# Privacy guard (PLAN.md section 4): fails if networking or image/video persistence APIs appear in
# shipped code. Scans the app target and SwayCore sources (tests excluded).
# Escape hatch for a reviewed false positive: append the comment `privacy-guard:allow` to that line.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERNS=(
  # Networking
  'URLSession' 'NSURLConnection' 'URLRequest' 'NSURLRequest' 'NSURLDownload'
  'import Network' 'NWConnection' 'NWListener' 'NWBrowser' 'NWEndpoint'
  'CFSocket' 'CFStreamCreatePairWithSocket' 'CFHTTP' 'SCNetworkReachability'
  'import WebKit' 'WKWebView' 'getaddrinfo' 'socket\(' 'connect\('
  'Data\(contentsOf: *URL\(string' 'String\(contentsOf: *URL\(string'
  # Persisting camera imagery
  'AVAssetWriter' 'AVCaptureMovieFileOutput' 'AVCapturePhotoOutput' 'AVCaptureStillImageOutput'
  'CGImageDestination' 'jpegData' 'pngData' 'heicData' 'tiffRepresentation'
)

regex=$(IFS='|'; echo "${PATTERNS[*]}")
hits=$(grep -rnE --include='*.swift' "$regex" Sway SwayCore/Sources 2>/dev/null | grep -v 'privacy-guard:allow' || true)

if [[ -n "$hits" ]]; then
  echo "Privacy guard FAILED. Networking or image-persistence APIs found:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "Privacy guard passed: no networking or image-persistence APIs in Sway/ or SwayCore/Sources/."
