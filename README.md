# Gander

**Look. Focus. Flow.** A quiet macOS menu bar utility that moves keyboard focus to the display you are
looking at, using head pose from the camera, entirely on-device. See PLAN.md (plan), SPEC.md (current phase),
CONTRACT.md (architecture), STATUS.md (progress).

Status: the app works end to end (M0–M7): head-pose tracking, switching, Focus Lock, guided setup, settings, and
hardening for sleep, display changes, and camera conflicts. The first release is built by `scripts/release.sh`
(see docs/RELEASING.md).

## Install

Download the DMG from the repository's **Releases** page, open it, drag Gander to Applications, and open it from
there. The early builds are not notarized, so macOS says Apple could not verify the app. Click **Done**, then open
System Settings → Privacy & Security, scroll to the Security section, and click **Open Anyway** next to "Gander was
blocked" (once; macOS 15 and later removed the right-click → Open shortcut). Or, in Terminal after copying Gander to
Applications: `xattr -dr com.apple.quarantine /Applications/Gander.app`. Gander lives in the menu bar; choose **Set Up…** in
its menu. There is no auto-update, because
Gander never uses the network: to update, download the new DMG and replace the app.

## Permissions

- **Camera:** head pose. Asked on first use.
- **Accessibility:** to raise and focus the last-used window on a display. Setup asks for it. It is tied to the
  app's signature, so a different build (Xcode, ad hoc, or the signed release) asks again.
- No Screen Recording, no network.

## Requirements

macOS 14+, Xcode 26+. No third-party dependencies. Keep the repo out of iCloud-synced folders such as
`~/Documents`: iCloud's file attributes make codesigning of test bundles fail.

## Build and run

```bash
open Gander.xcodeproj          # scheme "Gander", Run (signs with your Apple Development certificate)
```

Command line (unsigned):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Gander.xcodeproj -scheme Gander build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Gander.xcodeproj -scheme Gander test CODE_SIGNING_ALLOWED=NO   # all package tests
(cd GanderCore && swift test)
scripts/lint.sh && scripts/privacy-guard.sh
```

## Privacy

Frames are processed in memory and dropped. Nothing is written or sent anywhere; there is no networking code.
Numeric pose traces are saved only in DEBUG builds, to `~/Library/Application Support/Gander/Traces`. The cursor
is never moved, and Gander neither synthesizes nor globally monitors input events. Window titles are shown in the
Focus Test window only, never logged or stored. All of this is enforced in CI by `scripts/privacy-guard.sh`.

## Diagnostics and audits

`scripts/sleep-diag.sh` captures Gander's live log and thread samples across a sleep/wake, for hangs.
`scripts/audit-privacy.sh` checks the entitlements and the built app for any network access or image saving
(docs/PRIVACY-AUDIT.md). `scripts/soak.sh` records Gander's CPU, memory, and switches over a long run.
