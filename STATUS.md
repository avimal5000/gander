# Status

Phase: **M7 hardening is merged; M8 release pipeline is in PR #49.** Updated by the orchestrator.

**Current state (2026-10-26):** M6 (#48) and M7 (#50, 8aaf86c) are merged on `main`; the user approved the merges.
M8 (the release script, DMG, and release workflow) is in PR #49. Still open: **#40**, signing and notarization, until
the user adds a Developer ID certificate and the five repository secrets (docs/RELEASING.md), and **#39**, the
all-day soak test, which the user runs with `scripts/soak.sh`. The user's hardware checks for M6 and M7 (SPEC §9) are
still to do. Decisions: no auto-update, first version 0.1.0.

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| M7 audit (Opus) | Done | Report: blocker (sticky suspend), holds for display/Space changes, adaptive frame rate design, camera fallback and backoff |
| SPEC D43–D48, CONTRACT §6.1.1, §6.2.1, §6.5.5 | Done | |
| `SwayModels`: `SuspendReason.sessionInactive`, `PoseDemand`, `PoseSource.setDemand` | Done | Default no-op, so fakes compile |
| Privacy audit and soak tooling (#38, #39) | Done | `scripts/audit-privacy.sh`, `docs/PRIVACY-AUDIT.md`, `scripts/soak.sh` (57d28ef) |
| M7 builders | Done | All three finished and combined (29228a5). Full `xcodebuild test`: 1246 tests, zero warnings; lint and guard clean |
| M7 review (Opus) | Done | No blockers; privacy guarantee holds (every camera start goes through the sticky tracker). Should-fix: (1) the adaptive rate rounds to the camera's frame grid (Low Power Mode gave 7.5 fps, a 20 or 24 fps camera got 10 or 12): now a nominal schedule; (2) a failed restart during the USB fallback turned Tracking off; (3) lock/unlock distributed notifications may be delayed for an inactive app: register with `.deliverImmediately`. Minor: display hold had no cap or log; seed `.sessionInactive` at launch; test gaps. Accepted for the hardware check: a Space change during Sway's own switch resets the decider cooldown (pinned by a test); Center Stage mode is documented as per app but unconfirmed |
| M7 fixes | Done | All review items fixed by the same three builders (the limit reset at 5:20 am and they finished by 5:55): nominal frame schedule (Low Power Mode now a true 10 fps, 20/24 fps cameras get 15), lock/unlock delivered immediately, `.sessionInactive` seeded at launch, fallback restart failure keeps Tracking on, display hold capped at 3 s and logged, test gaps filled with mutation checks |
| M7 full verification, PR | Done | PR #50 open, CI green. Full `xcodebuild test`: 1282 tests, zero warnings; lint, guard, and a Release build (zero warnings, privacy audit passes). Waiting for the user's hardware check (SPEC §9) and merge. PR #49 (M8) is stacked on this branch |
| M8 release pipeline | Done, PR #49 | Worktree `.build-m8`, branch `feat/40-m8-release` (rebased onto main after M7 merged). `scripts/release.sh` builds a universal, hardened-runtime, ad-hoc-signed 0.1.0 DMG in 36 s (tested: mounts, version 0.1.0, camera entitlement only, privacy audit passes); signs with a Developer ID certificate and notarizes when given them. `.github/workflows/release.yml` on `v*` tags. `docs/RELEASING.md` has the user's morning steps. #43 (Sparkle) closed as not planned. #40 stays open until the user adds the certificate |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-camera-m7 | `CameraService` | CONTRACT §6.1.1: sticky suspend, sessionInactive, self-heal, retry backoff, Center Stage off | Sonnet | **Done** | 101 tests. Both old bugs fail the new tests when restored (mutation check). Known limit: a launch while already locked is not detected (no public API); Center Stage is switched off process-wide once the first session starts |
| builder-pose-m7 | `PoseEstimator`, `SwitchEngineTests` | CONTRACT §6.2.1: adaptive frame rate, 15 fps cap, power state | Sonnet | **Done** | 109 + 106 tests. Face-present switching is unchanged; away-then-back switches within 1 s + dwell. Low Power Mode quantizes 10 fps to 7.5 fps on a 15 fps camera, so one missed frame can restart the dwell there (accepted, reviewer to assess) |
| builder-ui-m7 | `SwayUI` | CONTRACT §6.5.5: display/Space holds, demand wiring, coalesced refresh, camera grace, USB fallback | Sonnet | **Done** | 669 tests (587 before); three existing tests changed as the contract requires. New `DelayScheduling` injection and `TrackingStatus.cameraDisconnected` |

### Earlier phases (done)

M6: builder-ui-m6 plus an Opus review (seven items, all fixed), PR #48. M4 + M5: PR #47. M2 + M3: PR #45.

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
