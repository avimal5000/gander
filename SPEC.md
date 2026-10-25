# Sway: Spec (current phase: M4 + M5)

Derived from PLAN.md, which stays the source of truth. Where this spec and PLAN.md differ, the difference is
listed in section 3 with its reason. CONTRACT.md defines the code-level interfaces.

## 1. Product

Sway is a quiet macOS menu bar utility. It switches keyboard focus to the display you are looking at, using
head pose from a camera, entirely on-device. It works per display: look at another monitor, dwell briefly,
and typing goes to the last-used window there. The cursor never moves.

## 2. Scope of this phase

M0–M3 are done (PRs #44 and #45). The M1 gate was **GO** on a C922 with 3 displays
(`docs/decisions/0001-m1-head-pose-gate.md`); M2 built the switch engine and M3 the focus controller, and the
user's Focus Test passed (`docs/focus-fallbacks.md`). This phase builds M4 and M5 together (D24).

| In this phase | Later |
|---|---|
| **M4 end-to-end loop:** camera → pose → decider → focus, the Tracking switch (Pause/Resume), Focus Lock and its global shortcut, menu bar status states (issues #19, #20, #22, #23) | M6 design pass (theme, icons, onboarding, edge glow, animation) |
| **M5 calibration + settings:** guided calibration in a Setup window, saved calibrations per display set and camera, a recalibrate prompt on unknown display setups, sensitivity, launch at login (issues #24–#27) | M7 hardening (sleep, hot-plug, camera conflicts, CPU targets, soak test); M8 release |

This is the first build that **moves focus automatically**. It does so only while Tracking is on, a calibration
fits the connected displays and camera, Accessibility is granted, and Focus Lock is off.

## 3. Decisions and assumptions

Earlier decisions still hold unless marked superseded:

| # | Decision | Source |
|---|---|---|
| D1 | Per-display focus (head pose cannot separate apps on one screen) | PLAN.md |
| D2 | One local package `SwayCore`, one module per area, plus a thin app target | User + PLAN.md |
| D3 | ~~The MVP tracks 2 displays~~ (superseded by D22). All logic is generic over N, with the limit only in `SwayPolicy.maxTrackedDisplays` | User |
| D5 | Private repo `avimal5000/sway`, labels, milestones, issues, CI on PRs | User |
| D6 | Bundle ID `com.avimal5000.sway`; Focus Lock default ⌃⌥⌘L (M4) | PLAN.md |
| D7 | Apple Development signing (team WNW4M84Z3U), hardened runtime, no App Sandbox | Assumption |
| D8 | Built-in camera by default, with a picker (the user tests with the C922) | Assumption |
| D9 | No live video preview | Assumption |
| D11 | macOS 14 deployment target; Xcode 26.6 | Environment |
| D12 | swift-format strict; SwiftLint in CI | Assumption |
| D14 | Build M2 and M3 together overnight without waiting for plan approval. The user reviews the plan and tests in the morning. Merge PR #44 once CI is green | User, 2026-10-25 |
| D15 | Live tracking computes Vision angles only. The landmark pass runs only during the gate test, which keeps both feature sets for comparison. Saves CPU (about 32% of one core with both) | User, 2026-10-25 |
| D16 | The user's M1 gate trace (numbers only: angles and timestamps) is committed as a test fixture | User, 2026-10-25 |
| D17 | (Superseded by D25.) Until M5's guided calibration, **the gate test is the calibration**. After each gate run (or opened trace), Sway fits a Vision-angles profile and keeps it in `UserDefaults`. It is stale when the display layout fingerprint changes | Assumption (lowest-friction path to a live preview) |
| D18 | The classifier finds the nearest calibrated display center in normalized (yaw, pitch) space, with pitch weighted no more than yaw. Uncertainty is a margin ratio, and an "elsewhere" box around all display centers catches looks at the keyboard or away. This is not a Gaussian likelihood: calibration only samples display centers, so per-display spreads are far narrower than real use, while nearest-center regions extend naturally to the screen edges. Pitch drifted 3–8° between the two gate rounds while yaw held within about 2° | Gate data |
| D19 | The last-used window on a display is its **topmost normal window in the window server's z-order**. This is stateless (no observers), and z-order is the system's own recency order. Focus uses only public APIs: an Accessibility raise plus frontmost, then app activation as the fallback, and the result is always verified | Assumption (PLAN.md risk 2) |
| D20 | CI fails if code moves the cursor, synthesizes or globally captures input events, or uses private window-server APIs (`scripts/privacy-guard.sh`) | PLAN.md "cursor never moved" |
| D21 | (Superseded by D22.) `maxTrackedDisplays` stays 2. M4 applies it through the decider's `targets`. The preview considers every calibrated display | User (D3) + PLAN.md |

New decisions for this phase:

| # | Decision | Source |
|---|---|---|
| D22 | Track up to **3 displays** (`SwayPolicy.maxTrackedDisplays = 3`). Applied through the decider's `targets`: the first 3 calibrated displays in layout order | User, 2026-10-25 (the gate showed all three of the user's displays separate cleanly) |
| D23 | At launch Sway restores Tracking as the user last set it (`sway.trackingEnabled`, default off). Only the user's own choices are saved; Sway turning tracking off by itself (a camera failure) does not change the saved choice. "Open Sway at login" is a setting, off by default | User, 2026-10-25 |
| D24 | Build M4 and M5 together on one branch with one PR, as D14 did for M2 + M3 | User, 2026-10-25 |
| D25 | **Calibrations are saved per display set and camera** (`CalibrationLibrary`, at most 24). A calibration covers any two or more of its displays, so unplugging a display (or closing the lid) keeps tracking on the rest. Arrangement and resolution changes keep it. A display set that no saved calibration covers is unknown: tracking waits, camera off, and the menu asks for a calibration. The existing gate-test profile is migrated. Replaces D17's fingerprint staleness | Issue #26 + orchestrator (a resolution change or a nudge in Displays settings does not move the monitors relative to the camera) |
| D26 | **Tracking is one switch.** On means tracking; off is Paused, with the camera off. The camera runs only while Tracking is on and a calibration fits, or while a calibration or gate test needs it. Replaces the "Live camera" toggle | PLAN.md definition of done ("camera light is on only while tracking is on") |
| D27 | **Focus Lock**: ⌃⌥⌘L toggles it from any app (configurable, Carbon `RegisterEventHotKey`, no permission). The camera stays on; no switch fires. Not saved: off at launch. The menu also has a Focus Lock switch | User-approved default |
| D28 | Automatic switching also holds while Sway itself is the active app (its menu or a window is in front), while a calibration, gate test, or Focus Test request runs, and while a focus request is in flight | Orchestrator (a look at another display while adjusting Sway's own settings must not pull focus away) |
| D29 | The decider's focused display comes from `focusedDisplay(in:)`, polled once a second and on every app activation, and is set to the target after a verified switch. After a failed or "no window" attempt on a display, Sway treats that display as focused until the focus really moves elsewhere or the look moves to another display. So a look at a display with no window does not retry every 0.75 s | Orchestrator |
| D30 | **Guided calibration**: 2 rounds over the displays, each look 1.5 s settle + 2.5 s hold (about 24 s for 3 displays), Vision angles only. Quality comes from the separability analyzer's Vision-angles verdict | User-approved default ("look at each display for about 4–5 s, under 30 s") |
| D31 | **Sensitivity settings**: hold time 0.2–1.5 s (default 0.4) and a 5-step "Switch confidence" from Relaxed to Strict (enter margin 0.15–0.45, stay margin half of it; the middle step equals the engine defaults). Everything else stays at `SwitchSettings.default` | User-approved default |
| D32 | Menu bar icons are SF Symbol placeholders until M6 | User-approved default |
| D33 | Settings is a regular window ("Sway Settings"), not SwiftUI's `Settings` scene, which an LSUIElement app cannot reliably open from its menu bar extra on macOS 14 | Orchestrator |

## 4. Features

M1–M3 features F1–F15 are unchanged except where noted: the "Live camera" toggle (F1, F5) becomes the Tracking
switch (F18); the gate test (F7) also saves its profile into the calibration library (F20); the Switch preview
(F11) now shows real tracking.

**F16. Tracking loop (M4, #19).** While Tracking is on and a calibration fits:
- every pose sample goes through the switch decider, with the focused display (D29), Focus Lock and the holds
  (D28), and the tracked displays (D22);
- when the decider fires, Sway focuses the last-used window on that display (M3's fallback list, verified) and
  logs the result: app, display, method, time. Window titles are never logged;
- one focus request at a time; while one is in flight, no other starts.

**F17. Focus Lock (M4, #23).** A menu switch and a global shortcut (default ⌃⌥⌘L, changeable in Settings) turn
it on and off. While on, the menu bar icon shows a lock and nothing switches.

**F18. Tracking switch, Pause/Resume, launch state (M4, #22, D23, D26).**
- The menu's Tracking switch: off is Paused, with the camera off and the indicator dark.
- The choice is saved and restored at launch.
- Turning Tracking on before camera permission is granted shows the permission explanation first (as F2).

**F19. Menu bar status (M4, #20).** One status, computed in this priority order (first match wins). Placeholder
symbols per D32:

| Status | When | Symbol | Status line |
|---|---|---|---|
| Camera blocked | Tracking on, camera permission denied or restricted | `exclamationmark.triangle` | "Camera access needed" |
| Camera failed | The camera reported a failure (shown until the next start) | `exclamationmark.triangle` | "Camera unavailable" |
| Paused | Tracking off, and no calibration or gate test running | `eye.slash` | "Paused" |
| Calibrating | A calibration or gate test runs | `scope` | "Calibrating" |
| One display | Fewer than 2 displays | `display` | "Only one display" |
| Needs calibration | No saved calibration fits | `questionmark.circle` | "Needs calibration" |
| Suspended | Sleep, displays asleep, or screen locked | `pause.circle` | the existing suspended text |
| Starting | The camera is starting | `eye` | "Starting camera" |
| Camera busy | The camera is interrupted (in use by another app, stalled, disconnected) | `exclamationmark.triangle` | "Camera busy" when another app has it, else the existing interruption text |
| Needs Accessibility | Accessibility not granted | `hand.raised` | "Needs Accessibility" |
| Focus Lock | Focus Lock on | `lock.fill` | "Focus Lock on" |
| Tracking | Running, face visible | `eye.fill` | "Tracking" |
| No face | Running, no face | `eye.trianglebadge.exclamationmark` | "No face" |

The popover, top to bottom (fixed width, constant height while tracking starts and stops):
1. "Sway" and the status line with the camera name.
2. At most one banner: camera permission (F2); first setup ("Sway needs a quick setup, about a minute." with
   **Set Up…**) when nothing is calibrated yet; an unknown display setup (F22); Accessibility needed
   (**Grant Access…**); a shortcut that could not be registered.
3. **Tracking** switch.
4. **Focus Lock** switch, with the shortcut shown.
5. One line: "Looking at <display>", "Looking elsewhere", "No face", or a dash when the camera is off.
6. Camera picker.
7. Calibrate…, Settings…, Pose Debug Window…, Head-Pose Gate Test…, Focus Test Window…, Quit Sway.

**F20. Guided calibration (M5, #24, D30).** A "Set Up Sway" window, in steps:
1. **Camera access**, skipped when granted.
2. **Accessibility**, skipped when granted; "Skip for now" is allowed (tracking then shows Needs Accessibility).
3. **Camera check**: the camera runs and Sway says whether it sees a face, whether to move closer or back, and
   whether to center the face, with the advice "Put the camera where it sees your face from every display. On
   top of the middle display works best." The camera picker is here too.
4. **Look at each display**: the gate test's overlays and timing per D30. Esc or Cancel stops it.
5. **Result**: "Calibration looks good", or which displays are close together (Fair) or hard to tell apart
   (Poor), with **Start tracking** and **Calibrate again**. A fit that fails is not saved and says why.

Setup from scratch takes under 2 minutes including permissions. A recalibration (permissions granted) opens at
step 3 and takes under 30 s.

**F21. Settings window (M5, #25).**
- **General:** Open Sway at login (with the system's "needs approval" state and a button to open Login Items).
- **Switching:** Hold time and Switch confidence (D31), with Restore Defaults. Changes apply at once.
- **Focus Lock shortcut:** Record, Reset to ⌃⌥⌘L, Clear. A shortcut needs Control, Option, or Command; one
  that another app already uses is refused with a message, and the previous one stays.
- **Camera:** the picker.
- **Calibrations:** each saved calibration (its displays, camera, and date), the one in use marked, Delete per
  row, and Calibrate….

**F22. Recalibrate prompt (M5, #26, D25).** When the connected displays (two or more) are not covered by any
saved calibration for the current camera, tracking waits with the camera off, the icon shows Needs calibration,
and the menu banner says "New display setup. Calibrate so Sway can switch between them." with **Calibrate
(about 20 s)…**, which opens Setup at step 3.

**F23. Per-camera calibration (M5, #27).** Calibrations are saved per camera. Choosing another camera uses that
camera's calibration for these displays, or asks for one ("No calibration for <camera> yet.").

## 5. User flows

**A. First setup (under 2 minutes).** Menu → Set Up… → allow the camera → grant Accessibility → camera check →
look at each display (about 24 s for 3) → "Calibration looks good" → Start tracking.

**B. Daily use.** Tracking is on from the last session. Look at another display and hold about 0.4 s: typing
goes to that display's last-used window, and the cursor stays where it was. Glances, the keyboard, and looking
away do nothing. ⌃⌥⌘L locks focus while reading across displays; ⌃⌥⌘L again unlocks.

**C. Display change.** Unplug a display: tracking continues on the rest. Plug in a display Sway has not seen
with these others: the icon shows Needs calibration; Calibrate (about 20 s)… → tracking resumes.

**D. Adjust.** Settings → Hold time or Switch confidence; the next look uses it. Settings → Focus Lock shortcut →
Record → press a new combination.

## 6. Privacy and behavior requirements (enforced)

- All earlier rules hold: frames stay in memory, no networking, numeric traces only and only in DEBUG, the
  cursor never moves, no input-event synthesis, no global input monitoring, no private APIs (D20).
- The camera runs only while Tracking is on and a calibration fits, or while a calibration or gate test needs it.
  Paused means the camera is off.
- The global shortcut uses Carbon `RegisterEventHotKey`: macOS delivers only that one key combination to Sway.
  There is no event tap, no global monitor, and no Input Monitoring permission. Recording a new shortcut uses a
  local key monitor inside the Settings window only, while recording.
- Window titles are never logged or stored; switch logs name the app and display only.
- The login item is the system's own (`SMAppService`); nothing else is installed.

## 7. Non-functional

- Swift 6 language mode, zero warnings, no third-party dependencies.
- A sustained look switches within `dwell + 1 frame` of the first qualifying sample, plus the focus request
  (verified or failed within about 700 ms).
- Tracking adds no per-frame main-thread work beyond the decider, and polls the focused display once a second.
  CPU with Tracking on and no windows open stays near the M3 figure (about 14–19% of one core).

## 8. Definition of done (this phase)

**M4 done when:**
- the tracking loop, Focus Lock, Tracking switch, launch state, and status pass the CONTRACT §6.5.2 tests (all
  against fakes; no test moves real focus);
- `SystemIntegration` passes CONTRACT §6.8;
- with Tracking on, a held look moves real focus without moving the cursor (user check).

**M5 done when:**
- Setup, Settings, the calibration library, the recalibrate prompt, and per-camera calibration pass CONTRACT
  §6.5.3;
- a recalibration takes under 30 s and first setup under 2 minutes (user check).

**Both:** the full `xcodebuild` build and test succeed with zero warnings; privacy guard, swift-format, and
SwiftLint pass; a reviewer has verified conformance to CONTRACT.md.

## 9. Manual checks the user must do (cannot be automated here)

1. Rebuild in Xcode (approve the keychain prompt if it appears). Accessibility may need re-granting if the
   signature changed.
2. **Setup:** Menu → Calibrate… → follow the steps. It should take under 30 s with permissions granted, and the
   result should say Good.
3. **Daily use**, with Tracking on:
   - hold a look at each display: focus moves to its last-used window, and the cursor never moves;
   - glances, the keyboard, and looking away: no switch;
   - ⌃⌥⌘L: the icon shows a lock and nothing switches; ⌃⌥⌘L again unlocks;
   - with Sway's menu or Settings in front: no switch.
4. **Pause:** Tracking off → the camera light goes off. Quit and relaunch: Tracking comes back as you left it.
5. **Displays:** unplug one display → tracking continues on the others; plug it back in → still calibrated.
6. **Settings:** change Hold time and feel the difference; record another Focus Lock shortcut; turn on Open at
   login (approve it in System Settings if asked), then log out and in.
7. CPU with Tracking on and no windows open: about the same as before (around 14–19%).
