# Privacy audit (issue #38)

Gander's privacy promise, as shown to the user on the welcome step and in the camera permission prompt: the camera stays
on this Mac, Gander reads only which way the head is turned, and video is never recorded, saved, or sent anywhere.

This page says how each part of the promise is checked, what was found, and how to re-check it. Re-run the checks
before every release: `scripts/audit-privacy.sh` (static) and `scripts/audit-privacy.sh --runtime` (while Gander runs).

Last run: 2026-10-25, Debug build of the M6 release (`6d85cfc`).

## The promise, claim by claim

| Claim | How it is enforced | Evidence | Result |
|---|---|---|---|
| No network access | No networking API is called in shipped code. No network entitlement, and no networking library linked. The app is not sandboxed (the Accessibility API cannot control other apps' windows from inside the sandbox), so the entitlements file and the missing symbols are the guarantee | `scripts/privacy-guard.sh` bans `URLSession`, `Network`, sockets, `WebKit`, and more in `Sway/` and `SwayCore/Sources/` (runs in CI); the audit checks that the only entitlement is `com.apple.security.device.camera`, that no binary links CFNetwork, WebKit, SystemConfiguration or Network, imports a socket, URL-session or reachability symbol, or embeds a URL; at runtime `lsof -i` on the Gander process shows no socket | Pass |
| No video or images are saved | No API that writes pixels or movies is called: the guard bans `AVAssetWriter`, `AVCaptureMovieFileOutput`, `AVCapturePhotoOutput`, `CGImageDestination`, `pngData`, `tiffRepresentation`, and similar. Frames are handed to Vision and released | The guard; at runtime the audit lists the files Gander holds open for writing, and none is an image or video (only the system's Metal shader cache) | Pass |
| What is saved holds numbers only | The calibration library (in `UserDefaults`) and the saved pose traces (`~/Library/Application Support/Sway/Traces/*.json`) hold head angles with timestamps, the display layout (names, sizes, positions) and the camera name. No pixels. Traces are written only by DEBUG builds (`FileTraceStore.save` is compiled out of Release builds, which throw `disabledInReleaseBuilds`), so a shipped Release build writes no trace file; DEBUG trace files are created owner-only (folder 0700, files 0600) | `PoseSample` is a timestamp and a head pose (yaw, pitch, roll); the 14 trace files on the developer's Mac were inspected | Pass |
| The camera runs only while it is needed | The camera is on only while Tracking is on and a calibration fits, or while Setup's camera check or calibration, the Pose Debug, or the Focus Test needs it. Paused means off. Sleep, display sleep, and screen lock turn it off, and wake turns it back on only if it was wanted | `SuspendTracker` tests (a reason set; nothing resumes after stop); about 30 model tests, for example `pausingTurnsTheCameraOffAndTheStatusToPaused`, `terminationStopsTheCamera`, `quitSwitchesTheCameraOffBeforeTerminating`, `theCameraRunsOnlyForTheCameraCheckAndTheCalibration`, `closingTheWindowStopsTheCameraWhenTrackingIsOff`; the audit's runtime step prints the camera start and stop lines to compare with your own toggles; the green camera light is the physical check | Pass (the hardware check is in the checklist below) |
| No input is read or faked | No event tap, no global key or mouse monitor, no `IOHIDManager`, no synthesized events, and the cursor never moves. The Focus Lock shortcut uses Carbon `RegisterEventHotKey`, which delivers only that one combination | The guard bans `CGEventTapCreate`, `CGEventPost`, `NSEvent.addGlobalMonitorForEvents`, `IOHIDManager`, and `CGWarpMouseCursorPosition`, `CGEvent(`, `.post(tap:`, `CGEventSource`; Gander asks for no Input Monitoring permission | Pass |
| Window titles are not stored | Switch logs name the app and the display only, and both are logged `privacy: .private(mask: .hash)`: the unified log shows a hash, not the name, unless private data logging is enabled on the Mac. Switch outcomes, methods and timings are `.public` | `logSwitch` in `AppModel+Tracking.swift`; `AppModelTrackingTests` and `AppModelFocusTestTests` check that a window titled "Secret page" never appears in the switch log or the Focus Test log | Pass |
| No private APIs | The guard bans the private window-server and Accessibility calls | The guard | Pass |
| No third-party code | Swift packages: none. The only dependency considered for later is Sparkle (M8); the audit fails if Sparkle is linked until that is decided on purpose | `Package.swift`, `otool -L` | Pass |

## Findings from this run

- No failures. Nothing in the code or the built app contradicts the promise.
- The app's only network-capable surface is Apple's own frameworks that link CFNetwork indirectly (Foundation). The
  app's own binary imports no socket, URL-session, or reachability symbol, so Gander cannot use them.
- Because the app is not sandboxed, the guarantee that it cannot reach the network rests on the guard, the
  entitlements, and these checks, not on the operating system. A future change that adds networking would have to
  change the guard, and a reviewer would see that.
- Files read back from disk are not trusted: a trace file larger than 50 MB is refused, display sizes from a trace are converted with a clamping helper (no trap on `1e300`), and a stored calibration with a zero, negative or non-finite scale is dropped, so tracking waits for a new calibration.
- The saved traces and the calibration hold the display names (for example "BenQ GW2490T") and the camera's name.
  These stay on the Mac; they are the only descriptive data Gander stores.

## How to re-run

```bash
# Static checks, after a build (pass --app for a Release build)
scripts/audit-privacy.sh [--app path/to/Gander.app]

# With Gander running: sockets, written files, camera start/stop lines. Toggle Tracking during the 30 seconds.
scripts/audit-privacy.sh --runtime 30
```

## Checks only a person can make

1. **Camera light:** turn Tracking off in the menu: the green light goes out within a second. Turn it on: the light
   comes on. Quit Gander: the light is out.
2. **Sleep and lock:** with Tracking on, lock the screen (⌃⌘Q): the light goes out. Unlock: it returns.
3. **System Settings → Privacy & Security → Camera:** Gander is listed, and nothing else was added by Gander (no
   Microphone, Input Monitoring, Screen Recording, or Full Disk Access entries).
4. **Little Snitch or `nettop -p $(pgrep -x Gander)`** while using Gander for a few minutes shows no connections.
