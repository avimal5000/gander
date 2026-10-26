# Status

Phase: **M7, hardening** (issues #33–#39) and, in parallel, **M8, release** (#40–#43). Updated by the orchestrator.

**Current state (2026-10-26, overnight):** M6 merged (#48, 6d85cfc); the user has gone to bed and asked to wait for
them before merging. Branch `feat/33-m7-hardening`: the privacy audit and soak tooling are committed. An Opus audit
of sleep/lock, hot-plug, camera conflicts, Spaces, and CPU found one blocker (the camera could turn on at the lock
screen, because suspend reasons were forgotten when capture stopped) and the fixes below. The user's decisions: no
auto-update, version 0.1.0, throttle with no face and in Low Power Mode, wait for them before merging, and sign in
the morning (they have a paid Apple Developer account but no certificate yet).

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| M7 audit (Opus) | Done | Report: blocker (sticky suspend), holds for display/Space changes, adaptive frame rate design, camera fallback and backoff |
| SPEC D43–D48, CONTRACT §6.1.1, §6.2.1, §6.5.5 | Done | |
| `SwayModels`: `SuspendReason.sessionInactive`, `PoseDemand`, `PoseSource.setDemand` | Done | Default no-op, so fakes compile |
| Privacy audit and soak tooling (#38, #39) | Done | `scripts/audit-privacy.sh`, `docs/PRIVACY-AUDIT.md`, `scripts/soak.sh` (57d28ef) |
| M7 builders | Running | builder-camera-m7, builder-pose-m7, builder-ui-m7 |
| M7 review (Opus), fixes, full verification, PR | Pending | |
| M8 release pipeline | Done, PR pending | Worktree `.build-m8`, branch `feat/40-m8-release` (based on the M7 branch because it uses the audit script). `scripts/release.sh` builds a universal, hardened-runtime, ad-hoc-signed 0.1.0 DMG in 36 s (tested: mounts, version 0.1.0, camera entitlement only, privacy audit passes); signs with a Developer ID certificate and notarizes when given them. `.github/workflows/release.yml` on `v*` tags. `docs/RELEASING.md` has the user's morning steps. #43 (Sparkle) closed as not planned. #40 stays open until the user adds the certificate |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-camera-m7 | `CameraService` | CONTRACT §6.1.1: sticky suspend, sessionInactive, self-heal, retry backoff, Center Stage off | Sonnet | Running | |
| builder-pose-m7 | `PoseEstimator`, `SwitchEngineTests` | CONTRACT §6.2.1: adaptive frame rate, 15 fps cap, power state | Sonnet | Running | |
| builder-ui-m7 | `SwayUI` | CONTRACT §6.5.5: display/Space holds, demand wiring, coalesced refresh, camera grace, USB fallback | Sonnet | Running | |

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
