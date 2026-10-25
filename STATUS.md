# Status

Phase: **M0 + M1** (stop at the M1 go/no-go gate). Updated by the orchestrator.

**Current state:** M1 is built, reviewed and verified, and the **M1 gate is GO** (2026-10-24, C922 camera, 3 displays:
weakest pair d′ 8.3, held-out accuracy 100%). Recorded in `docs/decisions/0001-m1-head-pose-gate.md`. Remaining:
the user's other visual/hardware checks, merging PR #44, and deciding on M2.

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| Read PLAN.md, clarify, write SPEC/CONTRACT/STATUS | Done | Answers: 2-display MVP with generic-N internals; stop after M1; full GitHub setup |
| Skeleton: Xcode project, SwayCore package, SwayModels, stubs | Done | Built and tested before any builder started |
| User approval of Phase 1 | Done | Approved 2026-10-24 |
| GitHub M0: private repo, labels, milestones, issues | Done | avimal5000/sway (private). 8 labels, M0–M8 milestones, issues #1–#42. #1, #3, #4 closed; #2 (CI) closes with the M1 PR |
| M1 branch | Done | `feat/5-m1-head-pose-spike` (issues #5–#9; #10 is the user's gate decision) |
| Integrate modules into app target | Done | `AppComposition` matched every module's public API, so no app code changes. Added `Config/Info.plist` (`NSCameraUseContinuityCameraDeviceType`), merged via `INFOPLIST_FILE` |
| Review pass (Opus) | Done | Verdict: ready for user testing. Two integration bugs fixed (stale stream events, launch-window request lifetime), plus duplicate statuses and the §6.2 eye-centroid revision |
| Orchestrator verification (clean build folders) | Done | Privacy guard pass; swift-format clean; `swift build` 0 warnings; `swift test` 361/361; `xcodebuild` Debug build, Debug test (361/361) and Release build all succeed with 0 warnings; launch probe: no stray windows, app stays up |
| Commit, push, PR | Done | CI runs on the PR |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-camera | `CameraService` | Capture, device selection, permission, sleep/lock suspend (CONTRACT 6.1) | Sonnet | **Done** | 63 tests. Accepted deviations: Continuity Camera excluded from `isBuiltIn`; fallback format needs width ≥ 640 only. Reviewer split one long type and function for lint (no behavior change) |
| builder-pose | `PoseEstimator` | Vision pose + landmark proxy, `LivePoseSource` (CONTRACT 6.2) | Sonnet | **Done** | 51 → 55 tests after review. Reviewer applied the eye-region centroids revision (pupils removed) and dropped consecutive duplicate statuses (one `.failed` per failed start) |
| builder-traces | `PoseTraces` | Store, replay, synthetic, separability analysis, Markdown (CONTRACT 6.3) | Sonnet | **Done** | 90 → 91 tests. Reviewer: `classify` ignores displays with no face samples (contract clarified), removed the CoreGraphics import |
| builder-displays | `DisplayTracker` | NSScreen layout + change stream (CONTRACT 6.4) | Sonnet | **Done** | 25 tests, no review changes. Duplicate display UUIDs fall back to `cg-<id>` |
| builder-ui | `SwayUI` | AppModel, menu bar, debug window, gate test + overlay, report (CONTRACT 6.5) | Sonnet | **Done** | 115 → 120 tests. Reviewer fixed the stale-stream race (a late `.stopped` hid "Failed" or disturbed a restarted run) and the LaunchWindowGuard request lifetime, and removed an unlisted import |
| reviewer | all | Contract conformance, full xcodebuild, warnings, tests, integration fixes | Opus | **Done** | Interrupted once by an account usage limit and resumed. All modules conform |

No builder was blocked, so no task needed a rerun on Opus.

## Test totals (final)

| Target | Tests |
|---|---|
| SwayModelsTests | 7 |
| CameraServiceTests | 63 |
| PoseEstimatorTests | 55 |
| PoseTracesTests | 91 |
| DisplayTrackerTests | 25 |
| SwayUITests | 120 |
| **Total** | **361** |

## Open issues

- **User checks (2026-10-25): passed.**
  - Gate run, overlays, C922 selection, no launch flashes, Live guess correct, and light mode all passed.
  - Sleep/wake: the camera turned off on sleep and back on after unlock (log-confirmed sequence systemSleep → screenLocked → resume → running).
  - Not explicitly reported: dark mode, and the light on Live-off and on quit.
- **One-time hang on sleep (not reproduced; M7).** On the first sleep attempt (2026-10-25 00:13), Sway's main thread hung about 3 s after the screen locked.
  - spindump logged `Sway [10201]: spin`, and powerd logged "Delays to Sleep notifications: [Sway timed out(30000 ms)]" three times.
  - The process never logged again, so the camera could not resume until the user relaunched it.
  - A rerun with live log streaming worked normally. No Sway code blocks the main thread, so the cause is still unknown; the leading suspect is the window/menu layer reacting to the screens sleeping.
  - Next time: run `scratchpad/tools/sleep-diag.sh`, which samples every thread when spindump reports a spin.
- **CPU:** about 2% idle and about 32% of one core with Live on and no window open. The cost is the Vision pipeline (face rectangles + landmarks at 15 fps), not the plot. The user approved dropping the landmark pass from live tracking (M2).
- **AppKit `-layoutSubtreeIfNeeded` warning** still appears once per launch. It also appears with the bare skeleton, so it comes from `MenuBarExtra`. Harmless unless it is linked to the hang above.
- **CI hang (fixed):** `swift test` hung on the macos-26 runner (5 virtual CPUs). A diagnostic run's stack sample showed every cooperative thread blocked in `VNImageRequestHandler.perform` waiting on Vision's internal task queue, which never completes on GitHub's virtualized Macs. The three tests that run real Vision now skip when `CI` is set; without them, all other tests passed on the runner in 0.5 s. Real Macs still run them.
- **M1 gate decision** (#10): **GO**, recorded. Implications for M2: Vision angles are the primary features; calibrate per camera; rely mainly on yaw (pitch std up to 4.1°). Three displays also separated cleanly, so raising `maxTrackedDisplays` to 3 is a later user decision. Not measured yet: glances, motion, day-to-day drift, the built-in camera.
- **Repo moved** from `~/Documents/Sway` (iCloud-synced, which broke test-bundle codesigning) to `~/Developer/Sway` on 2026-10-25. Plain in-repo `swift test` (361/361) and `xcodebuild` pass there. CONTRACT §4 now uses in-repo, gitignored scratch paths.
- **SwiftLint** has not run locally (not installed). CI runs it and reports warnings without failing; errors fail the job.
- Signed builds need a one-time keychain approval for `codesign` (user step, in Xcode). Verification builds are unsigned.
