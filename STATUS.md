# Status

Phase: **M2 + M3** (core engine + focus controller), built overnight per SPEC D14. Updated by the orchestrator.

**Current state:** Skeleton, SPEC, and CONTRACT for M2 + M3 are done on branch `feat/11-m2-m3-engine-focus`.
Builders are running.

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
| Skeleton | Done | SwayModels `Switching.swift`, `Focus.swift`, `includeLandmarks`; `SwitchEngine` and `FocusControl` stubs; fixture `Tests/SwitchEngineTests/Fixtures/gate-trace-2026-10-24.json`; guard now also blocks cursor/input-event and private APIs. Package builds; all tests pass; lint clean |
| Builders (4, Sonnet, parallel) | In progress | See below |
| Integrate into the app target | Pending | `AppComposition` gains `PoseSwitchEngine()` and `AXFocusController()` |
| `docs/focus-fallbacks.md` | Pending | From builder-focus's report |
| Review pass (Opus) | Pending | |
| Orchestrator verification, PR, CI | Pending | Keep CI runs few (macOS minutes bill at 10×) |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-engine | `SwitchEngine` | Profile fitting, classifier, switch state machine, synthetic and recorded-trace tests (CONTRACT §6.6; issues #11–#13) | Sonnet | In progress | |
| builder-focus | `FocusControl` | Window list z-order, coordinates, AX focus with fallbacks and verification (CONTRACT §6.7; issues #14, #15, #18) | Sonnet | In progress | |
| builder-pose | `PoseEstimator` | `includeLandmarks`: skip the landmark request in live tracking (CONTRACT §6.2) | Sonnet | In progress | |
| builder-ui | `SwayUI` | Landmarks only during the gate; calibration profile; switch preview; Accessibility onboarding; Focus Test window (CONTRACT §6.5.1; issues #16, #17) | Sonnet | In progress | |

## Open issues

- **One-time hang on sleep (M7, not reproduced).**
  - On the first sleep attempt (2026-10-25 00:13), Sway's main thread hung about 3 s after the screen locked.
  - spindump recorded a "spin", and powerd waited 30 s on Sway three times.
  - A rerun with live log capture worked normally.
  - Cause unknown; the leading suspect is the window/menu layer reacting to the screens sleeping.
- **CPU:** about 32% of one core with Live on (face rectangles + landmarks at 15 fps). This phase drops the
  landmarks from live tracking (D15); the user re-measures.
- **AppKit `-layoutSubtreeIfNeeded` warning** appears once per launch, from `MenuBarExtra`. Harmless.
- **Dependabot PR** (actions/checkout bump) is open; left for the user.
- **SwiftLint** is not installed locally; CI runs it.
- Signed builds need a one-time keychain approval for `codesign` (user step, in Xcode). Verification builds are unsigned.
