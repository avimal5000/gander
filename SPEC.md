# Sway: Spec (current phase: M2 + M3)

Derived from PLAN.md, which stays the source of truth. Where this spec and PLAN.md differ, the difference is
listed in section 3 with its reason. CONTRACT.md defines the code-level interfaces.

## 1. Product

Sway is a quiet macOS menu bar utility. It switches keyboard focus to the display you are looking at, using
head pose from a camera, entirely on-device. It works per display: look at another monitor, dwell briefly,
and typing goes to the last-used window there. The cursor never moves.

## 2. Scope of this phase

M0 and M1 are done. PR #44 was merged on 2026-10-25, and the M1 gate was **GO**: on a C922 with 3 displays,
the weakest pair scored d′ 8.3 and held-out accuracy was 100% (`docs/decisions/0001-m1-head-pose-gate.md`).
PLAN.md allows M2 and M3 to overlap, so this phase builds both.

| In this phase | Later |
|---|---|
| **M2 core engine:** calibration profile, pose classifier, switch decider, tests over synthetic and recorded traces, live "switch preview" | M4 end-to-end loop (camera → decider → focus), Focus Lock hotkey, Pause/Resume |
| **M3 focus controller:** last-used window per display, Accessibility onboarding, "focus display N" from a debug window, documented fallbacks | M5 guided calibration UI and settings; M6 design; M7 hardening; M8 release |

This phase still makes **no automatic focus changes**. Focus moves only when the user presses a button in the
Focus Test window. The decider runs live only as a preview.

## 3. Decisions and assumptions

M1 decisions D1–D13 still hold:

| # | Decision | Source |
|---|---|---|
| D1 | Per-display focus (head pose cannot separate apps on one screen) | PLAN.md |
| D2 | One local package `SwayCore`, one module per area, plus a thin app target | User + PLAN.md |
| D3 | The MVP tracks 2 displays. All logic is generic over N, with the limit only in `SwayPolicy.maxTrackedDisplays` | User |
| D5 | Private repo `avimal5000/sway`, labels, milestones, issues, CI on PRs | User |
| D6 | Bundle ID `com.avimal5000.sway`; Focus Lock default ⌃⌥⌘L (M4) | PLAN.md |
| D7 | Apple Development signing (team WNW4M84Z3U), hardened runtime, no App Sandbox | Assumption |
| D8 | Built-in camera by default, with a picker (the user tests with the C922) | Assumption |
| D9 | No live video preview | Assumption |
| D11 | macOS 14 deployment target; Xcode 26.6 | Environment |
| D12 | swift-format strict; SwiftLint in CI | Assumption |

New decisions for this phase:

| # | Decision | Source |
|---|---|---|
| D14 | Build M2 and M3 together overnight without waiting for plan approval. The user reviews the plan and tests in the morning. Merge PR #44 once CI is green | User, 2026-10-25 |
| D15 | Live tracking computes Vision angles only. The landmark pass runs only during the gate test, which keeps both feature sets for comparison. Saves CPU (about 32% of one core with both) | User, 2026-10-25 |
| D16 | The user's M1 gate trace (numbers only: angles and timestamps) is committed as a test fixture | User, 2026-10-25 |
| D17 | Until M5's guided calibration, **the gate test is the calibration**. After each gate run (or opened trace), Sway fits a Vision-angles profile and keeps it in `UserDefaults`. It is stale when the display layout fingerprint changes | Assumption (lowest-friction path to a live preview) |
| D18 | The classifier finds the nearest calibrated display center in normalized (yaw, pitch) space, with pitch weighted no more than yaw. Uncertainty is a margin ratio, and an "elsewhere" box around all display centers catches looks at the keyboard or away. This is not a Gaussian likelihood: calibration only samples display centers, so per-display spreads are far narrower than real use, while nearest-center regions extend naturally to the screen edges. Pitch drifted 3–8° between the two gate rounds while yaw held within about 2° | Gate data |
| D19 | The last-used window on a display is its **topmost normal window in the window server's z-order**. This is stateless (no observers), and z-order is the system's own recency order. Focus uses only public APIs: an Accessibility raise plus frontmost, then app activation as the fallback, and the result is always verified | Assumption (PLAN.md risk 2) |
| D20 | CI fails if code moves the cursor, synthesizes or globally captures input events, or uses private window-server APIs (`scripts/privacy-guard.sh`) | PLAN.md "cursor never moved" |
| D21 | `maxTrackedDisplays` stays 2. M4 applies it through the decider's `targets`. The preview considers every calibrated display | User (D3) + PLAN.md |

## 4. Features

M1 features F1–F9 (menu bar, camera permission and capture, pose estimation, Pose Debug window, trace
recording, gate test, separability report, re-analysis) are unchanged, except that F4 now computes landmark
angles only during the gate test (D15).

**F10. Calibration profile (M2).**
- After a gate test is analyzed, or a trace is opened, Sway fits a profile:
  - per display: mean yaw/pitch and spread;
  - axis scales;
  - the layout fingerprint and the camera name.
- The profile is saved and restored on launch.
- The UI shows when the profile is missing ("Run the gate test to calibrate") or stale ("Displays changed since
  calibration").

**F11. Switch preview (M2, Pose Debug window).** When Live is on and a profile exists:
- the nearest display with a margin bar, or "No face" / "Looking elsewhere";
- the decider phase: idle, dwelling (with a progress bar), or cooling down;
- the simulated focused display, which follows the decider's switches;
- a "Simulate Focus Lock" toggle;
- a log of the last 10 would-be switches, with time and dwell latency.

It never moves real focus.

**F12. Accessibility onboarding (M3).**
- Explains why Sway needs Accessibility: to move keyboard focus to a window on the display you look at. It never
  moves the cursor and never reads window contents.
- "Grant Access…" shows the system prompt and opens System Settings → Privacy & Security → Accessibility.
- The status refreshes on its own while visible.

**F13. Focus Test window (M3).**
- Each display in layout order, with its last-used window (app and title), refreshed every second while open.
  The currently focused display is marked.
- Per display: **Focus**, and **Focus in 3 s** (so the user can click into another app first). The countdown is
  cancellable.
- A log of the last 10 results:
  - "Focused Safari via Accessibility raise in 42 ms";
  - "No window on LG ULTRAGEAR";
  - "Accessibility permission needed";
  - "Failed: …".
- The buttons are disabled until Accessibility is granted.

**F14. Switch rules (M2 engine, no UI of its own).** A switch fires only when all of these hold:
- the face is detected with enough confidence;
- the pose is nearest a display other than the focused one, by at least the enter margin;
- the look is held for the dwell time (brief dropouts up to `maxGap` are tolerated, and the hold must keep at
  least the lower stay margin);
- Focus Lock is off;
- the cooldown after the previous switch has passed.

Glances, ambiguous poses, looks elsewhere, and a lost face never switch.

**F15. Focus fallbacks documented (M3, issue #18).** `docs/focus-fallbacks.md` lists what works and what does
not: Spaces, full-screen apps, apps that refuse activation, windows spanning displays, and minimized or hidden
windows. The user's Focus Test results fill it in.

## 5. User flows

**A. Calibrate and preview (M2).**
1. Live on → Head-Pose Gate Test → run it, and Sway saves a profile.
2. Pose Debug → Switch preview.
3. Look at another display and hold: the dwell bar fills, and after about 0.4 s a would-be switch is logged.
4. A quick glance logs nothing. So does looking down at the keyboard.

**B. Grant Accessibility (M3).** Menu → Focus Test Window → "Grant Access…" → system prompt → enable Sway in
System Settings → the status turns to Granted.

**C. Focus test (M3).**
1. Open a window on each display (for example Safari on the LG and Terminal on the BenQ).
2. Focus Test shows them.
3. Press "Focus in 3 s" for the LG, then click into Terminal.
4. After 3 s, Safari becomes the active window, and the cursor has not moved.

## 6. Privacy and behavior requirements (enforced)

- All M1 rules still hold: frames stay in memory, there is no networking, numeric traces only and only in DEBUG,
  and the camera runs only while needed.
- The cursor is never moved. There is no input-event synthesis, no global input monitoring, and no private
  APIs (D20).
- Window titles are read only to show them in the Focus Test window. They are never logged, stored, or sent.
- No Screen Recording permission. Window owners and bounds come from the window list; titles come from
  Accessibility.

## 7. Non-functional

- Swift 6 language mode, zero warnings, no third-party dependencies.
- The decider is pure and deterministic: time comes only from sample timestamps. A sustained look switches
  within `dwell + 1 frame` of the first qualifying sample.
- A focus attempt is verified, or reported as failed, within about 700 ms. Accessibility calls time out after
  0.5 s per app and never run on the main thread.

## 8. Definition of done (this phase)

**M2 done when:**
- `SwitchEngine` passes the CONTRACT §6.6 tests, including:
  - noise, ambiguity, glances, intentional looks, transit through a middle display, and looks elsewhere, over
    synthetic traces;
  - the user's recorded gate trace (fit on one round, replay the other: exactly the expected switches);
- the switch preview runs live in the Pose Debug window.

**M3 done when:**
- `FocusControl` passes the CONTRACT §6.7 tests;
- the Focus Test window lists last-used windows and focuses a display without moving the cursor;
- onboarding works;
- `docs/focus-fallbacks.md` exists.

**Both:**
- the full `xcodebuild` build and test succeed with zero warnings;
- privacy guard, swift-format, and SwiftLint pass;
- a reviewer has verified conformance to CONTRACT.md.

## 9. Manual checks the user must do (cannot be automated here)

1. Rebuild in Xcode (approve the keychain prompt if it appears).
2. Grant **Accessibility** to Sway when Focus Test asks. The grant is tied to the signed build.
3. **Calibrate:** run the gate test once (the profile then persists across launches).
4. **Switch preview:**
   - hold a look at each display: one logged switch per look, about 0.4 s after the head settles;
   - quick glances, looking at the keyboard, and turning partway: no switches;
   - with Simulate Focus Lock on: no switches.
5. **Focus Test**, with the cursor never moving:
   - focus each display, both immediately and with the 3 s delay from another app;
   - repeat with a full-screen app on one display, a second Space, and a window spanning two displays;
   - note what fails, for `docs/focus-fallbacks.md`.
6. Check CPU with Live on: it should drop below the ~32% seen with landmarks.
