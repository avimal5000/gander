# Status

Phase: **M2 + M3 merged** (core engine + focus controller). Next: **M4**, the end-to-end loop (PLAN.md). Updated by the
orchestrator.

**Current state:** M2 + M3 squash-merged into `main` as PR #45 (b9ab977, 2026-10-25); issues #11–#18 closed. The
user's hardware checks found high CPU and a crash on turning Live off; both were fixed and re-tested by the user. The
Focus Test passed. 638 tests, zero warnings.

## History

- **M2 + M3:** merged in PR #45 (2026-10-25). 638 tests.
- **M0 + M1:** merged in PR #44 (2026-10-25). 361 tests; the gate was **GO** (`docs/decisions/0001-m1-head-pose-gate.md`).
- **User hardware checks (2026-10-25), all passed:**
  - gate run, overlays, and C922 selection;
  - no launch flashes;
  - Live guess correct;
  - light mode;
  - camera off on sleep and back on after unlock.
- **User hardware checks of M2 + M3 (2026-10-25):**
  - Focus Test worked; light and dark mode fine; no flickers.
  - Full Focus Test passed: each display (immediate and after 3 s from another app), a full-screen app, a
    second Space, and a window spanning two displays. Results are in `docs/focus-fallbacks.md`.
  - CPU was 30–40% with Live on: fixed, see "CPU fix" below.
  - Crash when turning Live off from the menu: reproduced with a backtrace and fixed, see "Crash fix" below. The
    user's re-test passed (Live on 5+ minutes, then off from the menu bar).
- **CI hang fixed:** real-Vision tests hang on GitHub's virtual Macs, so they skip when `CI` is set.
- **Repo moved** to `~/Developer/Sway` (out of iCloud).

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| User decisions for overnight work | Done | Merge #44 when green; build M2 + M3 without waiting for plan approval; drop landmarks from live tracking; use the gate trace as a fixture |
| Merge PR #44 | Done | Squash-merged after green CI; issues #2, #5–#10 closed |
| SPEC / CONTRACT / STATUS for M2 + M3 | Done | SPEC D14–D21, F10–F15; CONTRACT §6.2 (landmarks flag), §6.5.1, §6.6, §6.7, §10–§12 |
| Skeleton | Done (e43db40) | SwayModels `Switching.swift`, `Focus.swift`, `includeLandmarks`; `SwitchEngine` and `FocusControl` stubs; fixture `Tests/SwitchEngineTests/Fixtures/gate-trace-2026-10-24.json`; guard now also blocks cursor/input-event and private APIs. Package builds; all tests pass; lint clean |
| Builders (4, Sonnet, parallel) | Done | See below |
| Integrate into the app target | Done | `AppComposition` passes `PoseSwitchEngine()` and `AXFocusController()` (Debug build succeeds, zero warnings); `SwitchEngineTests` and `FocusControlTests` added to the Sway scheme so `xcodebuild test` runs them |
| `docs/focus-fallbacks.md` | Done | Method, fallback list, and known limits (from builder-focus). The "verified" column holds the user's Focus Test results (2026-10-25): the four cases tested all work; the other rows are marked "Not tested". PR #45 now closes #15 and #18 |
| Review pass (Opus) | Done | Verdict: ready after fixes. No bugs found in the engine, focus controller, concurrency, or privacy. Fixed: (1) the preview's dwell latency after a dwell restarts on the same display (step 4(a2)); (2) closing the Focus Test window now cancels a focus request in flight. A rate limit interrupted the review once; it was resumed. Orchestrator follow-ups: no-face traces now report "not enough face samples" instead of "no Vision angles" (contract §6.6 step 3 and §6.5.1 amended); UI test defaults now live in the temp directory (they had left 664 `sway.ui.tests.*.plist` files in `~/Library/Preferences`; the user can delete them) |
| CPU fix after the user's checks | Done | Profiled with `sample` against the user's running app. Live on with no windows: **42–49% → about 14–19%** of one core; Pose Debug open: about 40–50% → about 32%. Causes and fixes: (1) `.windowResizability(.contentMinSize)` re-measured Pose Debug's whole content on every frame (37% of the main thread): the root frame now bounds both sides of each axis; (2) SwiftUI keeps closed windows' and the popover's views alive, so they kept redrawing: live content now draws only while its window is on screen (`WindowVisibilityReader`); (3) Swift Charts rebuilt ~150 trail marks per frame: the trail is a `Canvas` over a chart that redraws only when its domain or clusters change; (4) the numeric readouts refresh five times a second (`LiveReadout`); (5) Vision re-read its revision table on every frame because revision 3 was set even when it is the default (3% of a core). The menu readout is now always one line (dashes when off), so the popover keeps its height when Live is toggled. What's left with no windows open is about 75% Vision face detection at 15 fps; lowering it is M7 work (adaptive frame rate) |
| Crash fix after the user's checks | Done | The user's `bt all`: a stack overflow on the camera session queue, about 3,000 nested closure releases deep, inside `FrameSampleReceiver.disable()`. Cause: the frame handler sat bare in an `OSAllocatedUnfairLock<(@Sendable (CameraFrame) -> Void)?>`. A function type stored in a generic container is re-abstracted on every `withLock` call, so each frame wrapped the stored handler in two more thunks. The chain grew by about 30 links a second while Live ran, every frame called through all of it, and releasing it at teardown overflowed the 512 KB dispatch-thread stack. Either toggle could trigger it once Live had run long enough (roughly two minutes at 15 fps); the menu toggle just happened to be the one used after long runs. The handler is now a field of a small struct (`Delivery`), which has one fixed representation. Reproduced and confirmed in a standalone build: bare storage crashed after about 3,000 calls on a 512 KB stack and slowed about 30× over 22,000 calls; boxed stayed flat. 3 new tests: delivery stops at `disable()`, `disable()` releases the handler, and a 20,000-frame run then `disable()` on a 512 KB-stack thread (with the old storage this crashes the test process). No other lock or container in the code holds a bare closure |
| Orchestrator verification, PR, CI | Done | Verified locally: privacy guard, swift-format strict, zero warnings, `swift test` 626 tests, `xcodebuild test` TEST SUCCEEDED (8 targets), Release BUILD SUCCEEDED. **PR #45** (closes #11–#14, #16, #17; #15 and #18 stay open until the user's Focus Test). CI run 1 failed on one timing-dependent test (a 25 ms polling timeout ran out on the slow runner); fixed in `05a052b`. **CI run 2 green**: 626 tests, SwiftLint 0 violations, guard, app build |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-engine | `SwitchEngine` | Profile fitting, classifier, switch state machine, synthetic and recorded-trace tests (CONTRACT §6.6; issues #11–#13) | Sonnet | **Done** | 102 tests pass; lint and guard clean. **On the user's gate trace: 225/225 held-out samples classified correctly** in both directions (lowest margin 0.34, against a 0.30 enter margin). Exactly the 2 expected switches each way, each at 0.400 s (dwell 0.4 s). After review, a contract amendment added a 1 µs tolerance on time comparisons (timestamps around 3·10⁵ s rounded 0.4 s down to 0.39999999996, so a switch could fire a frame late) and a gap check (a camera stall starts a fresh dwell instead of firing at once); both are implemented and tested |
| builder-focus | `FocusControl` | Window list z-order, coordinates, AX focus with fallbacks and verification (CONTRACT §6.7; issues #14, #15, #18) | Sonnet | **Done** | 19 small files: pure parsing, filtering, geometry, selection, and frame matching; the fallback sequence runs against a fake platform in tests. 81 tests pass (re-run by the orchestrator); lint and guard clean. The window list was checked live on 3 displays. **AX raise and title paths are untested live** (no Accessibility in the agent's process), so the user's Focus Test is the first real run. Accepted deviations, now in CONTRACT: window-list fallback when AX can't read the focused window; "Cancelled" result. Known limits are in `docs/focus-fallbacks.md` |
| builder-pose | `PoseEstimator` | `includeLandmarks`: skip the landmark request in live tracking (CONTRACT §6.2) | Sonnet | **Done** | Pure `requestPlan(includeLandmarks:)` helper gates the landmark request; `LivePoseSource` already passed the flag; 5 new tests (plan, flag reaches the estimator both ways, default off, restart uses the new value). 60 tests pass locally and with `CI=true` (3 Vision tests skip). Lint and guard clean. No contract issues |
| builder-ui | `SwayUI` | Landmarks only during the gate; calibration profile; switch preview; Accessibility onboarding; Focus Test window (CONTRACT §6.5.1; issues #16, #17) | Sonnet | **Done** | 194 tests pass (mutation-checked: removing the landmark switch or the one-at-a-time guard fails tests); lint and guard clean. Accepted interpretations: the preview pauses during a gate test; Focus Lock goes through the decider's `.locked` phase (no reset); dwell latency counts from the first dwelling sample on a display; Focus Test polls only once opened from the menu; titles are cleared when the window closes. Visual checks listed in the morning summary |

## Open issues

- **One-time hang on sleep (M7, not reproduced).**
  - On the first sleep attempt (2026-10-25 00:13), Sway's main thread hung about 3 s after the screen locked.
  - spindump recorded a "spin", and powerd waited 30 s on Sway three times.
  - A rerun with live log capture worked normally.
  - Cause unknown; the leading suspect is the window/menu layer reacting to the screens sleeping.
  - If it recurs, run `scripts/sleep-diag.sh` before reproducing. It samples every thread when spindump reports a spin.
- **AppKit `-layoutSubtreeIfNeeded` warning** appears once per launch, from `MenuBarExtra`. Harmless.
- **Dependabot PR** (actions/checkout bump) is open; left for the user.
- **Leftover test files:** earlier UI test runs left `sway.ui.tests.*.plist` files in `~/Library/Preferences` (664). Fixed for future runs. The user can delete the old ones: `rm ~/Library/Preferences/sway.ui.tests.*.plist`.
- **SwiftLint** is not installed locally; CI runs it.
- Signed builds need a one-time keychain approval for `codesign` (user step, in Xcode). Verification builds are unsigned.
