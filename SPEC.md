# Gander: Spec (current phase: 0.1.x tuning, after M8)

Derived from PLAN.md, which stays the source of truth. Where this spec and PLAN.md differ, the difference is
listed in section 3 with its reason. CONTRACT.md defines the code-level interfaces.

## 1. Product

Gander is a quiet macOS menu bar utility. It switches keyboard focus to the display you are looking at, using
head pose from a camera, entirely on-device. It works per display: look at another monitor, dwell briefly,
and typing goes to the last-used window there. The cursor never moves.

## 2. Scope of this phase

**Now (0.1.x tuning).** M0–M8 are done and v0.1.0 is released (unsigned). After a day of use the user found switching
a little slow, mostly on a quick look back: a built-in 0.75 s pause after every switch plus the hold time. This phase
makes the timing adjustable (D49, F35). The earlier phase notes below are kept for the record.

### Earlier: M7

M0–M6 are done (PRs #44, #45, #47, #48): Gander tracks, switches focus, calibrates in Setup, has Settings, and has its
design. This phase is **M7, hardening** (issues #33–#39): make sleep, lock, display changes, camera conflicts,
Spaces, and CPU use behave, and audit privacy.

| In this phase | Later |
|---|---|
| Sleep, lock, and user switching keep the camera off (#33); display hot-plug (#34); camera conflicts and USB camera fallback (#35); full-screen and Spaces (#36); adaptive frame rate for CPU and battery (#37); privacy audit (#38); soak-test tooling (#39) | M8 release: signing, notarization, DMG, release workflow (auto-update is not planned, D48) |

Behavior while the user is present and looking around does not change: the same dwell, the same switching.

## 3. Decisions and assumptions

Earlier decisions still hold unless marked superseded:

| # | Decision | Source |
|---|---|---|
| D1 | Per-display focus (head pose cannot separate apps on one screen) | PLAN.md |
| D2 | One local package `SwayCore`, one module per area, plus a thin app target | User + PLAN.md |
| D3 | ~~The MVP tracks 2 displays~~ (superseded by D22). All logic is generic over N, with the limit only in `SwayPolicy.maxTrackedDisplays` | User |
| D5 | Private repo `avimal5000/gander`, labels, milestones, issues, CI on PRs | User |
| D6 | Bundle ID `com.avimal5000.sway`; Focus Lock default ⌃⌥⌘L (M4) | PLAN.md |
| D7 | Apple Development signing (team WNW4M84Z3U), hardened runtime, no App Sandbox | Assumption |
| D8 | Built-in camera by default, with a picker (the user tests with the C922) | Assumption |
| D9 | No live video preview | Assumption |
| D11 | macOS 14 deployment target; Xcode 26.6 | Environment |
| D12 | swift-format strict; SwiftLint in CI | Assumption |
| D14 | Build M2 and M3 together overnight without waiting for plan approval. The user reviews the plan and tests in the morning. Merge PR #44 once CI is green | User, 2026-10-25 |
| D15 | Live tracking computes Vision angles only. The landmark pass runs only during the gate test, which keeps both feature sets for comparison. Saves CPU (about 32% of one core with both) | User, 2026-10-25 |
| D16 | The user's M1 gate trace (numbers only: angles and timestamps) is committed as a test fixture | User, 2026-10-25 |
| D17 | (Superseded by D25.) Until M5's guided calibration, **the gate test is the calibration**. After each gate run (or opened trace), Gander fits a Vision-angles profile and keeps it in `UserDefaults`. It is stale when the display layout fingerprint changes | Assumption (lowest-friction path to a live preview) |
| D18 | The classifier finds the nearest calibrated display center in normalized (yaw, pitch) space, with pitch weighted no more than yaw. Uncertainty is a margin ratio, and an "elsewhere" box around all display centers catches looks at the keyboard or away. This is not a Gaussian likelihood: calibration only samples display centers, so per-display spreads are far narrower than real use, while nearest-center regions extend naturally to the screen edges. Pitch drifted 3–8° between the two gate rounds while yaw held within about 2° | Gate data |
| D19 | The last-used window on a display is its **topmost normal window in the window server's z-order**. This is stateless (no observers), and z-order is the system's own recency order. Focus uses only public APIs: an Accessibility raise plus frontmost, then app activation as the fallback, and the result is always verified | Assumption (PLAN.md risk 2) |
| D20 | CI fails if code moves the cursor, synthesizes or globally captures input events, or uses private window-server APIs (`scripts/privacy-guard.sh`) | PLAN.md "cursor never moved" |
| D21 | (Superseded by D22.) `maxTrackedDisplays` stays 2. M4 applies it through the decider's `targets`. The preview considers every calibrated display | User (D3) + PLAN.md |

M4 + M5 decisions:

| # | Decision | Source |
|---|---|---|
| D22 | Track up to **3 displays** (`SwayPolicy.maxTrackedDisplays = 3`). Applied through the decider's `targets`: the first 3 calibrated displays in layout order | User, 2026-10-25 (the gate showed all three of the user's displays separate cleanly) |
| D23 | At launch Gander restores Tracking as the user last set it (`sway.trackingEnabled`, default off). Only the user's own choices are saved; Gander turning tracking off by itself (a camera failure, quitting) does not change the saved choice (confirmed by the user). "Open Gander at login" is a setting, off by default | User, 2026-10-25 |
| D24 | Build M4 and M5 together on one branch with one PR, as D14 did for M2 + M3 | User, 2026-10-25 |
| D25 | **Calibrations are saved per display set and camera** (`CalibrationLibrary`, at most 24). A calibration covers any two or more of its displays, so unplugging a display (or closing the lid) keeps tracking on the rest. Arrangement and resolution changes keep it. A display set that no saved calibration covers is unknown: tracking waits, camera off, and the menu asks for a calibration. The existing gate-test profile is migrated. Replaces D17's fingerprint staleness | Issue #26 + orchestrator (a resolution change or a nudge in Displays settings does not move the monitors relative to the camera); confirmed by the user, 2026-10-25 |
| D26 | **Tracking is one switch.** On means tracking; off is Paused, with the camera off. The camera runs only while Tracking is on and a calibration fits, or while a calibration or gate test needs it. Replaces the "Live camera" toggle | PLAN.md definition of done ("camera light is on only while tracking is on") |
| D27 | **Focus Lock**: ⌃⌥⌘L toggles it from any app (configurable, Carbon `RegisterEventHotKey`, no permission). The camera stays on; no switch fires. Not saved: off at launch. The menu also has a Focus Lock switch | User-approved default |
| D28 | Automatic switching also holds while Gander itself is the active app (its menu or a window is in front), while a calibration, gate test, or Focus Test request runs, and while a focus request is in flight | Orchestrator (a look at another display while adjusting Gander's own settings must not pull focus away); confirmed by the user, 2026-10-25 |
| D29 | The decider's focused display comes from `focusedDisplay(in:)`, polled once a second and on every app activation, and is set to the target after a verified switch. After a failed or "no window" attempt on a display, Gander treats that display as focused until the focus really moves elsewhere or the look moves to another display. So a look at a display with no window does not retry every 0.75 s | Orchestrator |
| D30 | **Guided calibration**: 2 rounds over the displays, each look 1.5 s settle + 2.5 s hold (about 24 s for 3 displays), Vision angles only. Quality comes from the separability analyzer's Vision-angles verdict | User-approved default ("look at each display for about 4–5 s, under 30 s") |
| D31 | **Sensitivity settings**: hold time 0.2–1.5 s (default 0.4) and a 5-step "Switch confidence" from Relaxed to Strict (enter margin 0.15–0.45, stay margin half of it; the middle step equals the engine defaults). Everything else stays at `SwitchSettings.default` | User-approved default |
| D32 | Menu bar icons are SF Symbol placeholders until M6 | User-approved default |
| D33 | Settings is a regular window ("Gander Settings"), not SwiftUI's `Settings` scene, which an LSUIElement app cannot reliably open from its menu bar extra on macOS 14 | Orchestrator |

New decisions for this phase (M6):

| # | Decision | Source |
|---|---|---|
| D34 | **Native look with Gander accents**: system materials, fonts, and controls, following light and dark mode. Forest green is the accent; ivory, sage, and charcoal appear in the icon, the welcome step, and the glow | User, 2026-10-25 |
| D35 | **The accent is the user's choice** (Settings → Appearance): "Gander green" (default) or "Match macOS" (the system accent). Applied with SwiftUI `.tint`, because an asset-catalog accent color yields to a system accent the user picked; the app has no asset-catalog accent, so Match macOS under Multicolor shows the system default rather than green | User, 2026-10-25 + orchestrator |
| D36 | **App icon: option A, "Swing"**: an ivory arc swinging from a small sage point to a larger ivory point, on a forest-green rounded square | User picked A from three drawn options, 2026-10-25 |
| D37 | **Menu bar icon: the Swing mark** as a template image; state shows as small changes: Tracking (solid), Paused (dimmed, hollow end point), Focus Lock (lock badge), Needs you (dot). Replaces D32's SF Symbols | User, 2026-10-25 |
| D38 | **Edge glow**: after a verified switch, a thin Gander-green border around the newly focused display fades in and out in about 0.35 s. On by default, with a Settings switch. Click-through; never activates Gander or takes focus; shows on every Space and over full-screen apps | User, 2026-10-25 ("make sure there is a feature in settings that lets you disable it") |
| D39 | **Focus Lock notice**: when the shortcut toggles Focus Lock, a small "Focus Lock on" / "Focus Lock off" notice near the top of the focused display for about 1 s. On by default, with a Settings switch. The menu switch shows no notice (the change is in front of the user) | User, 2026-10-25 |
| D40 | **Welcome step**: Setup opens with a welcome on first setup (no saved calibration): the mark, one line on what Gander does, and the privacy promise | User, 2026-10-25 |
| D41 | **Restrained motion**: short fades for the glow, the notice, Setup step changes, and the menu banner. The menu bar icon does not animate (`MenuBarExtra` labels cannot animate reliably). With Reduce Motion on, nothing fades: the glow and notice just appear and disappear | User, 2026-10-25 + orchestrator |
| D42 | **Focus brings forward only the target window.** Gander raises the window, then activates its app with no options, which brings only the app's main and key windows forward. The Accessibility "frontmost" call, which can bring every window of the app forward, is now only the fallback. Measured on the user's Mac: activation from a background process brought only Terminal's front window | User report, 2026-10-25 (every Terminal window came forward over Discord) |

New decisions for this phase (M7):

| # | Decision | Source |
|---|---|---|
| D43 | **Suspension is sticky.** Sleep, display sleep, screen lock, and a fast user switch to another user are tracked for as long as Gander runs, including while the camera is off. The camera can therefore never start while the Mac is asleep or locked, even if Tracking, the displays, or the camera change in the meantime | Audit finding (the camera could turn on at the lock screen), 2026-10-26 |
| D44 | **Switching waits while displays or Spaces change.** From a display-change notification until the new layout is known (at most 0.75 s), and for 0.6 s after a Space change, Gander does not switch, then it polls the focused display again | Audit finding |
| D45 | **Adaptive frame rate.** At most 15 frames per second always. While Tracking, 5 per second after 2 s with no face, back to full within one frame when a face returns. Focus Lock and Needs Accessibility use 5 per second. In Low Power Mode or at a serious heat level: 10 per second with a face, 2 per second without. Calibration, the gate test, Setup's camera check, and Pose Debug always use the full rate. Nothing changes the switching speed while a face is present | User chose "no face + Low Power Mode", 2026-10-26 |
| D46 | **A missing USB camera falls back.** If the chosen camera is unplugged for 5 s, Gander uses a connected camera that has a calibration for these displays, and switches back when the chosen camera returns. With no calibrated camera to use, Gander turns Tracking off (in memory only, as for a camera failure, D23) and the menu says "<camera> disconnected". It does not turn Tracking back on by itself when the camera returns: the user does | User, 2026-10-26: after testing, "if not, it should just turn tracking off" | Orchestrator, from the audit's recommendation (user to confirm), 2026-10-26 |
| D47 | **Gentler retries and no Center Stage.** After a camera problem, retries start after 1 s and back off to 10 s (a stalled camera: up to 60 s). Gander turns Center Stage off for its own session so the framing cannot shift against the calibration | Audit finding |
| D48 | **No auto-update; first version 0.1.0.** Gander never uses the network, so there is no Sparkle. New versions are downloaded from GitHub Releases | User, 2026-10-26 |

Decision for tuning (0.1.x):

| # | Decision | Source |
|---|---|---|
| D49 | **Faster switching is adjustable.** A new setting, "Pause after a switch" (the decider's `cooldown`), range 0.2–1.5 s, default 0.75 s. The hold time's lower limit drops from 0.2 s to 0.05 s. A button applies "Instant" timing: hold time 0.10 s and pause 0.30 s, leaving the user's confidence setting alone. Defaults do not change, and saved settings without the new value keep working. Whether faster timing means more unwanted switches is measured with the all-day tool's count of quick back-and-forths | User asked "make the transition instant", 2026-10-26 |

An extra, uncalibrated display (a fourth monitor, Sidecar, AirPlay) still stops tracking until it is calibrated (D25).

## 4. Features

**F35. Switching timing (tuning, D49).** Settings → Switching gains **Pause after a switch** (a slider with its value,
for example "0.75 s": "How long Gander waits after switching before it will switch again. Shorter is faster for a quick
look back, but can bounce.") and a **Use Instant timing** button (hold 0.10 s, pause 0.30 s). The hold time slider
now goes down to 0.05 s. **Restore Defaults** restores all three values (0.40 s, 0.75 s, Balanced). Changes apply at
once.

**M7 features:**

**F30. The camera stays off when the Mac is asleep, locked, or in another user's session (#33, D43).** The menu
says "Suspended: …" and tracking resumes by itself, with no switch until you hold a look.

**F31. Display and Space changes (#34, #36, D44).** Plugging or unplugging a display, or changing Spaces, never
sends focus to the wrong window; switching resumes within a second.

**F32. Camera conflicts (#35, D46, D47).** Another app using the camera, or the camera unplugged, shows a clear
status and recovers on its own, with bounded retries. A missing USB camera falls back as D46 says, or turns
Tracking off when there is nothing to fall back to.

**F33. Lower CPU when you are away (#37, D45).** About 5% of one core or less with no face; the same switching speed
as before when you are there.

**F34. Privacy audit and soak test (#38, #39).** `docs/PRIVACY-AUDIT.md` and `scripts/audit-privacy.sh`;
`scripts/soak.sh` for the all-day test.


**M6 features (this phase):**

**F24. Theme and accent (#28, D34, D35).** Every Gander window and the menu use the accent the user chose. Gander green is
forest green in light mode and a lighter green in dark mode, so it keeps its contrast. Settings → Appearance →
Accent color: **Gander green** or **Match macOS**.

**F25. Icons (#29, D36, D37).** The app icon is the Swing mark. The menu bar icon shows the same mark in four states:

| Menu bar icon | Statuses (SPEC F19) |
|---|---|
| Tracking: solid | Tracking, No face, Calibrating, Starting |
| Paused: dimmed, hollow end point | Paused, One display, Suspended |
| Focus Lock: lock badge | Focus Lock |
| Needs you: dot | Camera blocked, Camera failed, Camera busy, Needs calibration, Needs Accessibility |

The menu's status line still names the exact status.

**F26. Welcome and Setup restyle (#30, D40).** On first setup, Setup opens with:
- the Swing mark;
- "Welcome to Gander";
- "Look at a display, and Gander moves your typing there. The pointer never moves.";
- "Your camera stays private. Gander reads only which way your head is turned, on this Mac. Video is never recorded,
  saved, or sent anywhere.";
- **Get Started**.

Every Setup step gets the same header (the mark and the step title) and layout.

**F27. Edge glow (#31, D38).** After a switch that focused a window, a 4 pt Gander-green border, softly glowing, traces
the edge of that display and fades out. Settings → Appearance → "Glow on the display that gets focus".

**F28. Focus Lock notice (#32, D39).** Pressing the Focus Lock shortcut shows a small notice with a lock symbol near
the top of the focused display: "Focus Lock on" or "Focus Lock off". Settings → Appearance → "Show a notice when
the shortcut toggles Focus Lock".

**F29. Motion (#32, D41).** Fades of about 0.2 s for Setup step changes and the menu banner; the glow and the notice
fade as F27 and F28 say. Reduce Motion turns every fade off.

**M1–M5 features:**

M1–M3 features F1–F15 are unchanged except where noted: the "Live camera" toggle (F1, F5) becomes the Tracking
switch (F18); the gate test (F7) also saves its profile into the calibration library (F20); the Switch preview
(F11) now shows real tracking.

**F16. Tracking loop (M4, #19).** While Tracking is on and a calibration fits:
- every pose sample goes through the switch decider, with the focused display (D29), Focus Lock and the holds
  (D28), and the tracked displays (D22);
- when the decider fires, Gander focuses the last-used window on that display (M3's fallback list, verified) and
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
1. "Gander" and the status line with the camera name.
2. At most one banner: camera permission (F2); first setup ("Gander needs a quick setup, about a minute." with
   **Set Up…**) when nothing is calibrated yet; an unknown display setup (F22); Accessibility needed
   (**Grant Access…**); a shortcut that could not be registered.
3. **Tracking** switch.
4. **Focus Lock** switch, with the shortcut shown.
5. One line: "Looking at <display>", "Looking elsewhere", "No face", or a dash when the camera is off.
6. Camera picker.
7. Calibrate…, Settings…, Pose Debug Window…, Head-Pose Gate Test…, Focus Test Window…, Quit Gander.

**F20. Guided calibration (M5, #24, D30).** A "Set Up Gander" window, in steps:
1. **Camera access**, skipped when granted.
2. **Accessibility**, skipped when granted; "Skip for now" is allowed (tracking then shows Needs Accessibility).
3. **Camera check**: the camera runs and Gander says whether it sees a face, whether to move closer or back, and
   whether to center the face, with the advice "Put the camera where it sees your face from every display. On
   top of the middle display works best." The camera picker is here too.
4. **Look at each display**: the gate test's overlays and timing per D30. Esc or Cancel stops it.
5. **Result**: "Calibration looks good", or which displays are close together (Fair) or hard to tell apart
   (Poor), with **Start tracking** and **Calibrate again**. A fit that fails is not saved and says why.

Setup from scratch takes under 2 minutes including permissions. A recalibration (permissions granted) opens at
step 3 and takes under 30 s.

**F21. Settings window (M5, #25).**
- **General:** Open Gander at login (with the system's "needs approval" state and a button to open Login Items).
- **Switching:** Hold time and Switch confidence (D31), with Restore Defaults. Changes apply at once.
- **Focus Lock shortcut:** Record, Reset to ⌃⌥⌘L, Clear. A shortcut needs Control, Option, or Command; one
  that another app already uses is refused with a message, and the previous one stays.
- **Camera:** the picker.
- **Calibrations:** each saved calibration (its displays, camera, and date), the one in use marked, Delete per
  row, and Calibrate….

**F22. Recalibrate prompt (M5, #26, D25).** When the connected displays (two or more) are not covered by any
saved calibration for the current camera, tracking waits with the camera off, the icon shows Needs calibration,
and the menu banner says "New display setup. Calibrate so Gander can switch between them." with **Calibrate
(about 20 s)…**, which opens Setup at step 3.

**F23. Per-camera calibration (M5, #27).** Calibrations are saved per camera. Choosing another camera uses that
camera's calibration for these displays, or asks for one ("No calibration for <camera> yet.").

## 5. User flows

**A. First setup (under 2 minutes).** Menu → Set Up… → allow the camera → grant Accessibility → camera check →
look at each display (about 24 s for 3) → "Calibration looks good" → Start tracking.

**B. Daily use.** Tracking is on from the last session. Look at another display and hold about 0.4 s: typing
goes to that display's last-used window, and the cursor stays where it was. Glances, the keyboard, and looking
away do nothing. ⌃⌥⌘L locks focus while reading across displays; ⌃⌥⌘L again unlocks.

**C. Display change.** Unplug a display: tracking continues on the rest. Plug in a display Gander has not seen
with these others: the icon shows Needs calibration; Calibrate (about 20 s)… → tracking resumes.

**D. Adjust.** Settings → Hold time or Switch confidence; the next look uses it. Settings → Focus Lock shortcut →
Record → press a new combination.

## 6. Privacy and behavior requirements (enforced)

- All earlier rules hold: frames stay in memory, no networking, numeric traces only and only in DEBUG, the
  cursor never moves, no input-event synthesis, no global input monitoring, no private APIs (D20).
- The camera runs only while Tracking is on and a calibration fits, or while a calibration or gate test needs it.
  Paused means the camera is off.
- The global shortcut uses Carbon `RegisterEventHotKey`: macOS delivers only that one key combination to Gander.
  There is no event tap, no global monitor, and no Input Monitoring permission. Recording a new shortcut uses a
  local key monitor inside the Settings window only, while recording.
- Window titles are never logged or stored; switch logs name the app and display only.
- The login item is the system's own (`SMAppService`); nothing else is installed.
- The camera never runs while the Mac is asleep, its displays are asleep, the screen is locked, or another user's
  session is active, whatever else changes meanwhile (D43). After the displays change, the camera may stay on for up
  to 2 s before it stops for lack of a calibration that fits (this avoids a blinking light while a dock re-attaches).
- The glow and the Focus Lock notice (M6) are click-through overlay panels: they never become key or main, never
  activate Gander, and sit above the normal window layer, so focus switching never picks them.

## 7. Non-functional

- Swift 6 language mode, zero warnings, no third-party dependencies.
- A sustained look switches within `dwell + 1 frame` of the first qualifying sample, plus the focus request
  (verified or failed within about 700 ms).
- Tracking adds no per-frame main-thread work beyond the decider, and polls the focused display once a second.
  CPU with Tracking on and no windows open stays near the M3 figure (about 14–19% of one core).
- The glow and the notice (M6) do no work between switches: their panels are reused, drawn only while shown, and add
  nothing per frame.

## 8. Definition of done (this phase)

**M7 done when:**
- CONTRACT §6.1 (suspend), §6.2 (adaptive frame rate), and §6.5.5 pass their tests, against fakes: no test touches a
  real camera, power setting, or display;
- the full `xcodebuild` build and test succeed with zero warnings; privacy guard, swift-format, and SwiftLint pass;
  a reviewer has verified conformance to CONTRACT.md;
- `scripts/audit-privacy.sh` passes and `docs/PRIVACY-AUDIT.md` is current;
- the user has run the hardware checks below, and the soak test has been started.

## 9a. Tuning check (D49)

Settings → Switching → **Use Instant timing**, then use Gander as usual and look back and forth between two displays:
a quick return should now take about half a second instead of about a second. Run `scripts/soak.sh sample` for a day
with it on and compare the report's "quick reversals" with an earlier day: more of them means more unwanted switches,
and the pause or hold time should go back up. **Restore Defaults** undoes it.

## 9. Manual checks the user must do (cannot be automated here)

Run `scripts/sleep-diag.sh 1800` in Terminal before the sleep checks.

1. **Lock:** Tracking on; lock with ⌃⌘Q. The camera light goes out within a second and the menu says "Suspended:
   screen locked". Unlock: the light and "Tracking" return within about 2 s, and nothing switches until you hold a look.
2. **The old bug:** lock the screen, unplug a display (or the USB camera) for 5 s, plug it back in, wait 10 s while
   still locked. The camera light must stay **off**.
3. **Display sleep and system sleep:** `pmset displaysleepnow`, then move the mouse; then Apple menu → Sleep and wake.
   Same results as 1. Close and reopen the lid, on battery and (if you use it) in clamshell mode.
4. **Display changes:** with 3 displays tracking, unplug one. Switching works between the other two with no
   wrong-display switch. Plug it back in: all three work within about 2 s. A resolution change or rearranging keeps
   the calibration.
5. **Cameras:** open Photo Booth, FaceTime, or Zoom while Tracking: the status stays sensible and their video is
   smooth. Select the USB camera, unplug it, wait 10 s: Gander falls back to a calibrated camera, or turns Tracking off
   with "<camera> disconnected" when there is none.
6. **Full-screen apps and Spaces:** make an app full screen on one display and look at it: typing goes there and the
   glow shows over it. Switch Spaces on another display while looking around; focus never lands in the wrong window.
7. **CPU:** Build Release (Product → Profile, or Archive), run it outside Xcode, and read Gander's CPU in Activity
   Monitor: with you at the desk, then away for 30 s. Away should be about 5% or less; at the desk about 15% or less.
   Sit back down: "Tracking" within a second, and a look switches as quickly as before. Try Low Power Mode.
8. **Soak:** run `scripts/soak.sh sample` for a working day, then `scripts/soak.sh report <file>`, and note any
   switch you did not want.
