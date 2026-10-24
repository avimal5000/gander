# Sway

**Look. Focus. Flow.** A quiet macOS menu bar utility that moves keyboard focus to the display you are
looking at, using head pose from the camera, entirely on-device. See PLAN.md (plan), SPEC.md (current phase),
CONTRACT.md (architecture), STATUS.md (progress).

Current phase: **M1 head-pose spike**. Measures whether head pose separates your displays (go/no-go gate).
No focus switching yet.

## Requirements

macOS 14+, Xcode 26+. No third-party dependencies.

## Build and run

```bash
open Sway.xcodeproj          # scheme "Sway", Run (signs with your Apple Development certificate)
```

Command line (unsigned):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Sway.xcodeproj -scheme Sway build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Sway.xcodeproj -scheme Sway test CODE_SIGNING_ALLOWED=NO   # all package tests
(cd SwayCore && swift test)
scripts/lint.sh && scripts/privacy-guard.sh
```

## Privacy

Frames are processed in memory and dropped. Nothing is written or sent anywhere; there is no networking code
(enforced in CI by `scripts/privacy-guard.sh`). Numeric pose traces are saved only in DEBUG builds, to
`~/Library/Application Support/Sway/Traces`.
