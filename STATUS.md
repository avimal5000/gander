# Status

Phase: **M4 + M5** (end-to-end loop + calibration and settings), built together per SPEC D24. Updated by the
orchestrator.

**Current state:** branch `feat/19-m4-m5-loop-calibration`. SPEC, CONTRACT, the shared types, and the
`SystemIntegration` stub are done (b9933fa). Builders are running.

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
  - CPU was 30–40% with Live on: fixed in c358c05 (about 45% → 17% with no windows open; details in PR #45).
  - Crash when turning Live off from the menu: a stack overflow from a closure chain that grew every frame; fixed
    in a40424f. The user's re-test passed (Live on 5+ minutes, then off from the menu bar).
- **User decisions for M4 + M5 (2026-10-25):** track 3 displays (D22); restore Tracking at launch, Open at login
  off by default (D23); build M4 + M5 together in one PR (D24); the proposed defaults for Focus Lock, Pause,
  icons, calibration, and sensitivity (D27, D30–D32). The user asked to be reached by phone when a decision is
  needed while away (push notifications; there is no SMS tool).
- **CI hang fixed:** real-Vision tests hang on GitHub's virtual Macs, so they skip when `CI` is set.
- **Repo moved** to `~/Developer/Sway` (out of iCloud).

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| Decisions | Done | See History (2026-10-25) |
| SPEC / CONTRACT | Done (b9933fa) | SPEC D22–D33, F16–F23; CONTRACT §6.5.2 (M4 UI), §6.5.3 (M5 UI), §6.8 (`SystemIntegration`), §7, §10–§12 |
| Skeleton | Done (b9933fa) | SwayModels `CalibrationLibrary.swift`, `SwitchSensitivity.swift`, `SystemIntegration.swift` (30 model tests); `maxTrackedDisplays = 3`; `SystemIntegration` stub in the package and scheme; the guard also blocks `IOHIDManager`. Two SwayUI gate tests still assume a limit of 2 (builder-ui-m4 updates them) |
| Builders | Running | builder-system done; builder-ui-m4 running, then builder-ui-m5. Both builders stopped once at the account's usage limit (reset 14:20) and resumed with their work intact |
| Integrate into the app target | Pending | `AppComposition` passes `CarbonHotKeyCenter()` and `MainAppLoginItem()` |
| Review pass (Opus) | Pending | |
| Verification, PR, CI | Pending | |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-system | `SystemIntegration` | Carbon hot key center and login item (CONTRACT §6.8; issue #23) | Sonnet | **Done** | 8 small files; the registry owns the Carbon handles behind a lock and runs handlers outside it, so a handler may re-register. 34 tests pass (pure mapping, invalid shortcuts, login item routing against a fake); lint and guard clean. The orchestrator added a guard so asking for the login item's current state calls nothing (the system would only report an error). **The live hot key and `SMAppService` paths are untested** (CONTRACT 12): the user's manual check |
| builder-ui-m4 | `SwayUI` | Tracking loop, Tracking switch and launch state, Focus Lock and shortcut, status, menu, calibration library (CONTRACT §6.5.2; issues #19, #20, #22, #23) | Sonnet | Running | |
| builder-ui-m5 | `SwayUI` | Setup window, Settings window, prompts, per-camera calibration (CONTRACT §6.5.3; issues #24–#27) | Sonnet | Waiting for builder-ui-m4 | |

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
