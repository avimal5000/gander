# Gander: Build Plan

**Look. Focus. Flow.** A quiet macOS menu bar utility that switches keyboard focus to the monitor you are looking at, using head pose from the built-in camera, entirely on-device.

Status: planning only. No code until the go-ahead.

## 1. Decisions locked in

| Topic | Decision |
|---|---|
| Distribution | Personal use first; signed/notarized GitHub Releases later (needs paid Apple Developer account then) |
| Mac App Store | Not a target (sandbox blocks cross-app window control) |
| Repo | `avimal5000/gander`, private, GitHub as source of truth + automation |
| Dev machine | MacBook Air M4, macOS 26.6.2, built-in + external 2560x1440 display. Xcode must be installed (user step) |
| Setup coverage | Layout varies day to day, so calibration and layout-change handling are core, not optional |
| Detection | Head pose only (Vision yaw/pitch/roll) for v1. Eye gaze deferred |
| Which window | Last-used window on the target display (tracked per display) |
| Cursor | Never moved. Only focus changes |
| Feedback | Menu bar icon state + optional thin forest-green edge glow (~300 ms) on the target display. Silent |
| Out of scope (MVP) | Workspace profiles, Smart Focus Zones, 3+ monitors, eye gaze, Mac App Store |

## 2. Tech stack (zero third-party dependencies)

- Swift 6, SwiftUI for UI, AppKit where needed. `MenuBarExtra`, `LSUIElement` (no Dock icon). Minimum macOS 14.
- `AVFoundation`: low-res capture (about 640x480, 10-15 fps), running only while tracking is enabled.
- `Vision`: `VNDetectFaceLandmarksRequest` for face presence and head yaw/pitch/roll. All local.
- Accessibility API (`AXUIElement`) + `NSWorkspace`/`NSRunningApplication` to track and raise windows.
- `NSScreen` for monitor geometry and change notifications.
- Global hotkey for Focus Lock via Carbon `RegisterEventHotKey` (no package needed).
- `os.Logger` for local-only logs. `UserDefaults` for settings. No network code anywhere.
- Quality: SwiftLint + swift-format, XCTest/Swift Testing.

## 3. Architecture

A local Swift package `GanderCore` (pure logic, testable with `swift test`, no camera needed) plus a thin app target.

```
Gander.app (SwiftUI shell: menu bar, settings, onboarding, glow overlay)
 └─ GanderCore
     ├─ CameraService        capture session, start/stop on tracking state, sleep/lock/lid aware
     ├─ PoseEstimator        Vision frame -> HeadPose(yaw, pitch, roll, faceConfidence)
     ├─ PoseSource (protocol) live camera OR replayed pose trace OR synthetic (tests)
     ├─ CalibrationModel     per-monitor pose profiles -> P(monitor | pose) with confidence margin
     ├─ SwitchDecider        pure state machine: dwell delay, confidence threshold,
     │                       hysteresis, cooldown, focus lock, "uncertain = do nothing"
     ├─ DisplayTracker       monitor layout, change detection, flags stale calibration
     ├─ WindowTracker        last-used window per display (via activation + AX frames)
     ├─ FocusController      raise + activate target window, no cursor movement
     └─ Settings / Permissions
```

Key rule: the decider only fires when the best monitor beats the runner-up by a margin, the face is clearly detected, the dwell timer completes, and focus lock is off. Anything else means no switch.

## 4. Privacy guarantees (enforced, not just promised)

- Frames are processed in memory and dropped. Nothing is written to disk or sent anywhere. Only numeric pose traces (no images) may be saved, and only in debug builds.
- Camera session exists only while tracking is on. Pause, sleep, screen lock, and quit stop it (the green camera indicator goes off).
- No network entitlement or code. CI includes a guard that fails if `URLSession`/networking APIs appear in the app target.
- No accounts, analytics, or crash-reporting services.

## 5. Biggest risks (to retire early)

1. **Head-only signal quality.** A glance with only the eyes will not register, and the external screen may sit close to the built-in one. Milestone 1 measures separability on your real setup before we build anything on top. This is a go/no-go gate.
2. **Reliably giving a window keyboard focus.** macOS 14+ restricts cross-app activation. Milestone 3 proves `AXRaise` + activation works across apps, Spaces, and full-screen, with a documented fallback list.
3. **Calibration drift.** Posture, chair, and screen position change daily. Quick recalibration plus layout-change detection must be low-friction.
4. **Testing without a camera in CI.** Solved by the `PoseSource` abstraction with replayable numeric traces; real-camera checks stay a manual checklist.
5. **CPU/battery.** Low fps, small frames, adaptive throttling when the face is idle or absent. Measure with Instruments.
6. **Camera busy.** Zoom/FaceTime may hold the camera. Gander must degrade gracefully and show it.

## 6. Milestones (each becomes a GitHub milestone with issues)

| # | Milestone | Outcome / exit criteria |
|---|---|---|
| M0 | Foundations | Xcode installed; private repo; app + `GanderCore` skeleton; CI, lint, templates, labels, milestones, issues seeded from this plan |
| M1 | Head-pose spike (go/no-go) | Debug window shows live yaw/pitch; trace recorder; you look at each display and we confirm the signals separate clearly. Decision recorded in the repo |
| M2 | Core engine | `CalibrationModel` + `SwitchDecider` with unit tests over synthetic and recorded traces: no false switches on noise, fast enough on intentional looks |
| M3 | Focus controller | Per-display last-used window tracking; Accessibility onboarding; "switch to display N" works from a debug button without moving the cursor |
| M4 | End-to-end loop | Menu bar app: camera -> pose -> decider -> focus. Pause/Resume, Focus Lock hotkey, status icon. First real daily-driver build |
| M5 | Calibration + settings | Guided calibration (layout, camera position, distance), sensitivity (delay, thresholds), recalibrate prompt on display changes |
| M6 | Design pass | Forest green / sage / ivory / charcoal theme, app + menu bar icons, onboarding, edge glow, restrained animation, light/dark |
| M7 | Hardening | Sleep/wake, lid close, display hot-plug, camera conflicts, full-screen/Spaces, CPU/battery targets, privacy audit, multi-hour soak test |
| M8 | Release (later) | Signing, notarization, DMG, release workflow on tag, optional auto-update (Sparkle, the one dependency we would consider) |

Suggested order of operations: M0 -> M1 (gate) -> M3 and M2 can overlap -> M4 -> M5 -> M6 -> M7 -> M8.

## 7. GitHub automation

Set up in M0 with `gh` (already authenticated as `avimal5000`, scopes repo + workflow):

- Repo creation, labels (`area/camera`, `area/focus`, `area/ui`, `area/privacy`, `risk`, `spike`), milestones M0-M8, and issues generated from this plan by script.
- **CI (GitHub Actions, macOS runner):** build, `swift test` on `GanderCore`, SwiftLint/swift-format, privacy guard (no networking APIs). Runs on pull requests only to conserve minutes.
- Branch-per-issue workflow: `feat/<issue>-slug`, PR template with a privacy/behavior checklist, squash merge, conventional commit titles.
- Issue templates: bug, feature, and a "calibration report" (setup, layout, what failed).
- Dependabot for Actions versions. Release workflow on `v*` tags (M8).
- Optional: a GitHub Projects board (needs one extra token scope: `gh auth refresh -s project`).

Caveats: on a private repo with the Free plan, macOS runner minutes are billed at a 10x multiplier (roughly 200 real minutes/month of the 2,000 included) and branch protection is not enforceable, so CI discipline is by convention. Making the repo public later removes both limits.

## 8. Definition of done for the MVP

- Look at the other monitor, dwell about the configured delay, and typing goes to the last-used window there, with the cursor and selections untouched.
- Ambiguous poses, glances, face lost, camera busy, or focus lock on: no switch.
- Camera light is on only while tracking is on. Verified no video written and no network access.
- Setup in under 2 minutes including permissions and calibration; recalibration in under 30 seconds.

## 9. Open items before M0

1. Install Xcode (App Store or developer.apple.com), then run `sudo xcode-select -s /Applications/Xcode.app` and open it once to accept the license.
2. Bundle identifier (proposal: `com.avimal5000.gander`; changeable until release).
3. Default Focus Lock shortcut (proposal: Control-Option-Command-L; configurable).
4. Do you want the Projects board (extra `gh` scope) or milestones + labels only?
