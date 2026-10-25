# Sway

**Look. Focus. Flow.** A quiet macOS menu bar utility that moves keyboard focus to the display you are
looking at, using head pose from the camera, entirely on-device. See PLAN.md (plan), SPEC.md (current phase),
CONTRACT.md (architecture), STATUS.md (progress).

Current phase: **M2 + M3**: the switch engine (calibration and decider) and the focus controller. The M1 gate
was GO (`docs/decisions/0001-m1-head-pose-gate.md`). Focus moves only from the Focus Test window's buttons;
automatic switching arrives in M4.

## Permissions

- **Camera:** head pose. Asked on first use.
- **Accessibility:** to raise and focus the last-used window on a display. Grant it from the Focus Test window
  (menu → Focus Test Window…). It is tied to the signed build, so run from Xcode.
- No Screen Recording, no network.

## Requirements

macOS 14+, Xcode 26+. No third-party dependencies. Keep the repo out of iCloud-synced folders such as
`~/Documents`: iCloud's file attributes make codesigning of test bundles fail.

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

Frames are processed in memory and dropped. Nothing is written or sent anywhere; there is no networking code.
Numeric pose traces are saved only in DEBUG builds, to `~/Library/Application Support/Sway/Traces`. The cursor
is never moved, and Sway neither synthesizes nor globally monitors input events. Window titles are shown in the
Focus Test window only, never logged or stored. All of this is enforced in CI by `scripts/privacy-guard.sh`.

## Diagnostics

`scripts/sleep-diag.sh` captures Sway's live log and thread samples across a sleep/wake, for hangs.
