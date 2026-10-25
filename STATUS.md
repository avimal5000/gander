# Status

Phase: **M2 + M3** (core engine + focus controller), built overnight per SPEC D14. Updated by the orchestrator.

**Current state:** Skeleton, SPEC, and CONTRACT for M2 + M3 are done on branch `feat/11-m2-m3-engine-focus`.
All four builders are done; the app builds with everything wired in. Review is next.

## History

- **M0 + M1:** merged in PR #44 (2026-10-25). 361 tests; the gate was **GO** (`docs/decisions/0001-m1-head-pose-gate.md`).
- **User hardware checks (2026-10-25), all passed:**
  - gate run, overlays, and C922 selection;
  - no launch flashes;
  - Live guess correct;
  - light mode;
  - camera off on sleep and back on after unlock.
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
| Integrate into the app target | In progress | `AppComposition` passes `PoseSwitchEngine()` and `AXFocusController()` (compiles once builder-ui lands the new `AppModel.init`); `SwitchEngineTests` and `FocusControlTests` added to the Sway scheme so `xcodebuild test` runs them |
| `docs/focus-fallbacks.md` | Done | Method, fallback list, and known limits (from builder-focus); the "verified" column awaits the user's Focus Test |
| Review pass (Opus) | Pending | |
| Orchestrator verification, PR, CI | Pending | Keep CI runs few (macOS minutes bill at 10×) |

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
- **CPU:** about 32% of one core with Live on (face rectangles + landmarks at 15 fps). This phase drops the
  landmarks from live tracking (D15); the user re-measures.
- **AppKit `-layoutSubtreeIfNeeded` warning** appears once per launch, from `MenuBarExtra`. Harmless.
- **Dependabot PR** (actions/checkout bump) is open; left for the user.
- **SwiftLint** is not installed locally; CI runs it.
- Signed builds need a one-time keychain approval for `codesign` (user step, in Xcode). Verification builds are unsigned.
