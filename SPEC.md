# Sway: Spec (current phase: M0 + M1)

Derived from PLAN.md, which stays the source of truth. Where this spec and PLAN.md differ, the difference is
listed in section 3 with its reason. CONTRACT.md defines the code-level interfaces.

## 1. Product

Sway is a quiet macOS menu bar utility. It switches keyboard focus to the display you are looking at, using
head pose from a camera, entirely on-device. It works per display: look at another monitor, dwell briefly,
and typing goes to the last-used window there. The cursor never moves.

## 2. Scope of this phase

PLAN.md makes M1 a go/no-go gate. This build therefore delivers **M0 + M1 only** and stops at the gate.

| In this phase | Later (after the gate decision) |
|---|---|
| M0: repo, Xcode app + SwayCore skeleton, CI, lint, templates, labels, milestones, seeded issues | M2 CalibrationModel + SwitchDecider |
| M1: camera capture, Vision head pose, pose debug window, trace recorder, guided gate test with separability report | M3 WindowTracker, FocusController, Accessibility |
| | M4 end-to-end loop, Focus Lock hotkey, M5 calibration UI and settings |
| | M6 design pass, M7 hardening, M8 release |

M1 makes **no focus changes** and needs **no Accessibility permission**.

## 3. Decisions and assumptions for this phase

| # | Decision | Source |
|---|---|---|
| D1 | Per-display focus, as PLAN.md says (not "which app": head pose cannot separate apps on one screen) | PLAN.md |
| D2 | One local package `SwayCore` with one module per area plus a thin app target | User + PLAN.md |
| D3 | MVP tracks 2 displays. All logic is generic over N, and the limit lives only in `SwayPolicy.maxTrackedDisplays`. The M1 gate measures **all** connected displays pairwise. | User |
| D4 | Stop after M1; the user runs the gate before M2 | User |
| D5 | Full GitHub M0 setup: private repo `avimal5000/sway`, labels, milestones M0–M8, issues, CI on PRs. No Projects board. | User |
| D6 | Bundle ID `com.avimal5000.sway`; Focus Lock default ⌃⌥⌘L (M4) | PLAN.md proposals |
| D7 | Signed with the existing Apple Development certificate (team WNW4M84Z3U), manual style, hardened runtime, no App Sandbox | Assumption |
| D8 | Built-in camera by default; picker for the C922 / Continuity Camera | Assumption (PLAN says built-in) |
| D9 | No live video preview in the debug window. A schematic face box shows framing. | Assumption (privacy, simplicity) |
| D10 | The gate evaluates two signals: Vision angles and a landmark-geometry proxy, in case Vision's angles are coarse | Assumption (retires risk 1 better) |
| D11 | Deployment target macOS 14; built with Xcode 26.6 on macOS 27.0.1 (PLAN.md listed 26.6.2) | Environment |
| D12 | Lint: swift-format (bundled with Xcode). SwiftLint config included; SwiftLint runs in CI and locally only if installed. | Assumption |
| D13 | Extra labels `area/core` and `area/infra` alongside PLAN.md's six | Assumption |

## 4. Features (M1)

**F1. Menu bar app.** `LSUIElement` (no Dock icon). A menu bar icon reflects camera/pose state. The menu offers:
live camera toggle, current status line, camera picker, "Pose Debug Window…", "Head-Pose Gate Test…",
"Quit Sway".

**F2. Camera permission.** When the camera is first needed, Sway explains why, then triggers the system
prompt. If access is denied, Sway shows how to enable it and offers a button that opens System Settings >
Privacy & Security > Camera.

**F3. Camera capture.** About 640×480 at 15 fps; late frames are dropped. The capture session exists only while
the live toggle is on or a gate test is running. System sleep, display sleep, and screen lock tear down the
session (camera light off), and it resumes afterwards. Quitting stops it. If the camera disconnects, is taken
by another app, or stops delivering frames, Sway shows that and recovers when it can.

**F4. Pose estimation.** For every frame, the largest face yields yaw, pitch, roll, face confidence, the face
box, and a landmark-derived yaw/pitch proxy. "No face" is a valid result.

**F5. Pose Debug window.**
- Live yaw, pitch, and roll, plus the landmark proxies, face confidence, a face-detected indicator, measured
  fps, camera name, and status.
- A plot of the last ~10 s of yaw vs pitch, switchable between Vision and landmark features.
- After a gate test: cluster ellipses per display, plus a **live guess** of the display the current pose is
  nearest to, with its normalized distance and the runner-up's.

**F6. Free trace recording (DEBUG builds only).** Record/Stop saves an unlabeled numeric trace (JSON) to
`~/Library/Application Support/Sway/Traces`, with a "Reveal in Finder" button. Release builds hide the
control and never write traces.

**F7. Guided gate test.**
- Lists the connected displays. The user picks rounds (default 2, range 1–3) and hold time (default 5 s,
  range 3–10 s).
- For each round and each display in left-to-right order, a full-screen overlay on that display shows a
  forest-green border, a centered target, and "Look at the center of this screen". A 1.5 s settle countdown
  runs, then the hold phase records samples labeled with that display. Settle samples are discarded.
- Esc or Cancel aborts at any time and removes all overlays.
- Requires at least 2 displays. With more than `maxTrackedDisplays`, an info note explains that v1 will
  track 2 and the test measures all.
- Starts the camera if needed and restores its previous state afterwards.

**F8. Separability report.**
- The overall verdict (GO / MARGINAL / NO-GO / insufficient data), and for each feature set: per-display
  stats, pairwise d′, held-out accuracy, notes, and a scatter plot colored by display.
- "Copy Markdown Summary" produces text for `docs/decisions/0001-m1-head-pose-gate.md`.
- In DEBUG builds the trace is saved automatically.

**F9. Re-analysis.** "Open Trace…" loads a saved trace and shows its report. Saved traces also feed the live
guess.

## 5. User flows

**A. First run.** Launch → menu bar icon (camera off) → Pose Debug Window → turn on the camera → permission
explanation → system prompt → live numbers appear and the camera indicator is on. Turn off → camera indicator off.

**B. Gate test (the M1 exit criterion).** Menu → Head-Pose Gate Test → check displays and settings → Start
→ follow the overlay on each display, round by round → report. If GO: copy the summary into the decision
record. Then open the debug window and look around, and the live guess should track the display you are
looking at.

**C. Re-analyze.** Gate window → Open Trace… → pick a saved trace → report.

**D. Interruptions.** Lock the screen during capture → camera off (status "Suspended: screen locked") →
unlock → capture resumes. Unplug an external camera that is in use → status shows "interrupted" → plug it
back in → recovery.

## 6. Privacy requirements (enforced)

- Frames are processed in memory and dropped. No images or video are ever written, displayed as video, or
  logged.
- Only numeric pose traces may be saved, and only in DEBUG builds.
- No networking code anywhere. `scripts/privacy-guard.sh` fails the build in CI if networking or
  image-persistence APIs appear.
- No accounts, analytics, or crash reporting. Logs use `os.Logger` locally only.
- The camera session exists only while it is needed (F3).

## 7. Non-functional

- Swift 6 language mode, zero warnings in our code, no third-party dependencies.
- Pose processing keeps up with 15 fps on an M4 (estimate < 30 ms per frame).
- UI updates are smooth; observable state updates are capped at the frame rate.

## 8. Definition of done (this phase)

**M0 done when:**
- the private repo `avimal5000/sway` exists with this code pushed;
- labels, milestones M0–M8, and issues are seeded; CI, templates, and Dependabot are committed;
- `xcodebuild` builds the app and `swift test` passes.

**M1 done (engineering) when:**
- F1–F9 are implemented per CONTRACT.md;
- every module's tests pass, the full `xcodebuild` build and test succeed with zero warnings in our code, and
  `scripts/privacy-guard.sh` and swift-format lint pass;
- a reviewer has verified every module against CONTRACT.md.

**M1 gate (user, on real hardware) when:**
- the debug window shows live yaw/pitch;
- the gate test has run on the real setup;
- the verdict is recorded in `docs/decisions/0001-m1-head-pose-gate.md`.

M2 starts only after a GO, or after a MARGINAL with an agreed change.

## 9. Manual checks the user must do (cannot be automated here)

1. Approve the keychain prompt on the first signed build in Xcode ("Always Allow").
2. Grant Camera permission on first use.
3. Visually check the menu bar, the debug window, and the gate overlays on each display, in light and dark mode.
4. Confirm the camera indicator turns off when the toggle is off, on screen lock, and on quit.
5. Run the gate test and record the decision.
