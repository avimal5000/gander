#!/usr/bin/env bash
# Privacy and behavior guard (PLAN.md sections 1 and 4): fails if networking, image/video persistence,
# cursor movement, input-event synthesis or capture, subprocesses, other image encoders, package dependencies, or
# private window-server APIs appear in shipped code. It is a line-based grep: a call split across lines can slip past.
# Scans the app target and GanderCore sources (tests excluded).
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
  # The cursor is never moved, and Gander neither synthesizes nor captures input events
  'CGWarpMouseCursorPosition' 'CGDisplayMoveCursorToPoint' 'CGAssociateMouseAndMouseCursorPosition'
  'CGEventPost' 'CGEventCreateMouseEvent' 'CGEventCreateKeyboardEvent' 'CGEventTapCreate' 'CGEvent\.tapCreate'
  'NSEvent\.addGlobalMonitorForEvents' 'IOHIDManager'
  # (NSBitmapImageRep itself and in-app local key monitors are fine: the menu bar icon and the shortcut field use them.)
  # Image encoders other than the ones above, event posting, screen capture, subprocesses and scripting
  'representation\(using' 'write(PNG|JPEG|TIFF|HEIF|HEIF10)Representation'
  'CGImageSourceCreate' 'CGWindowListCreateImage' 'ScreenCaptureKit' 'SCStream' 'CGDisplayCreateImage'
  'CGEvent\(' 'CGEventSource' '\.post\(tap' 'NSEvent\.addGlobalMonitor'
  '(^|[^A-Za-z0-9_])Process\(' 'NSTask' 'NSAppleScript' 'NSUserAppleScriptTask' 'posix_spawn' 'dlopen\(' 'NWPathMonitor'
  # No private window-server or Accessibility APIs
  '_AXUIElementGetWindow' 'CGSSetFrontProcess' '_SLPSSetFrontProcess' 'SLPSSetFrontProcess' 'SLSSetFrontProcess'
)

regex=$(IFS='|'; echo "${PATTERNS[*]}")
hits=$(grep -rnE --include='*.swift' "$regex" Gander GanderCore/Sources 2>/dev/null | grep -v 'privacy-guard:allow' || true)

# Package manifests: a dependency (remote or local) would put unreviewed code in the app, and no manifest should
# declare one. GanderCore/Package.swift has none today.
manifest_hits=$(grep -nE '\.package\(|https?://|git@' Package.swift GanderCore/Package.swift 2>/dev/null \
  | grep -v 'privacy-guard:allow' || true)
if [[ -n "$manifest_hits" ]]; then
  hits="${hits:+$hits$'\n'}${manifest_hits}"
fi

if [[ -n "$hits" ]]; then
  echo "Privacy guard FAILED. Forbidden APIs found (networking, image persistence, cursor/input events, private APIs):" >&2
  echo "$hits" >&2
  exit 1
fi
echo "Privacy guard passed: no networking, image-persistence, cursor/input-event or private APIs in Gander/ or GanderCore/Sources/."
