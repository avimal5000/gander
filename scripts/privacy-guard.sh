#!/usr/bin/env bash
# Privacy and behavior guard (PLAN.md sections 1 and 4): fails if networking, image/video persistence,
# cursor movement, input-event synthesis or capture, or private window-server APIs appear in shipped code.
# Scans the app target and SwayCore sources (tests excluded).
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
  # The cursor is never moved, and Sway neither synthesizes nor captures input events
  'CGWarpMouseCursorPosition' 'CGDisplayMoveCursorToPoint' 'CGAssociateMouseAndMouseCursorPosition'
  'CGEventPost' 'CGEventCreateMouseEvent' 'CGEventCreateKeyboardEvent' 'CGEventTapCreate' 'CGEvent\.tapCreate'
  'NSEvent\.addGlobalMonitorForEvents' 'IOHIDManager'
  # No private window-server or Accessibility APIs
  '_AXUIElementGetWindow' 'CGSSetFrontProcess' '_SLPSSetFrontProcess' 'SLPSSetFrontProcess' 'SLSSetFrontProcess'
)

regex=$(IFS='|'; echo "${PATTERNS[*]}")
hits=$(grep -rnE --include='*.swift' "$regex" Sway SwayCore/Sources 2>/dev/null | grep -v 'privacy-guard:allow' || true)

if [[ -n "$hits" ]]; then
  echo "Privacy guard FAILED. Forbidden APIs found (networking, image persistence, cursor/input events, private APIs):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "Privacy guard passed: no networking, image-persistence, cursor/input-event or private APIs in Sway/ or SwayCore/Sources/."
