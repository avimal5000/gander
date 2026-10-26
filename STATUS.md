# Status

Phase: **M6, the design pass** (theme, icons, welcome, edge glow, motion; issues #28–#32). Updated by the
orchestrator.

**Current state:** branch `feat/28-m6-design`. M4 + M5 merged as PR #47 (974c9f7); the user's hardware check passed.
The user made the M6 design decisions (SPEC D34–D41) and picked icon option A, "Swing", from drawn options
(https://claude.ai/artifact/PgqPsH9GcpEbK3onhqPSPm). Built, reviewed, and fixed; the Terminal focus fix is in too. Next: the PR and the user's check on their Mac.

## History

- **M4 + M5:** merged in PR #47 (2026-10-25). 984 tests. The user's hardware check passed ("working great").
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
- **User hardware check of M4 + M5 (2026-10-25):** passed; the user reported it "working great".

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| Decisions | Done | SPEC D34–D41 (2026-10-25): native look with a user-chosen accent; icon A "Swing"; menu bar mark with state badges; edge glow and Focus Lock notice, each on by default with a Settings switch; welcome step; restrained motion |
| SPEC / CONTRACT | Done | SPEC F24–F29, §8–§9; CONTRACT §6.5.4 |
| App icon + AccentColor asset | Done | `scripts/make-appicon.swift` renders option A "Swing" at every size (thicker strokes at 16 and 32 px) into `AppIcon.appiconset`; the asset-catalog AccentColor was later removed (see builder row) |
| Builder | Done | builder-ui-m6. Full `xcodebuild test`: 1073 tests, zero warnings |
| Review pass (Opus) | Done | No blockers; behavior unchanged, overlays can't take focus. To fix: (1) hard-coded forest tints in `SetupCalibratingStep:34`, `GateRunningView:38`, `SwitchPreviewView:75,91`, `GateOverlayView:64` override the accent; (2) no test pins the `OverlayPanel` invariants (non-activating, never key/main, `.screenSaver`, collection behavior); (3) `NoticePillView:58` mask closure is main-actor isolated but AppKit may draw it off-main: make it a `nonisolated static func`; (4) a cancelled fade can still `orderOut` a newly shown panel: check `Task.isCancelled` after the sleep in `pause`; (5) the glow is a full-screen Canvas (about 59 MB at 5K): draw edge strips instead; (6) `MenuBarIconTests:156-160` cut-out region has no ink in `.tracking` either: use `CGRect(x: 14.4, y: 4.6, width: 0.4, height: 0.4)`; (7) nits: this table's asset note, `CONTRACT.md:453`, `SettingsView.swift:6` is 126 columns |
| Fixes | Done | All seven review items (06551e9): the accent now reaches every progress bar; the glow is eight thin edge layers (no full-screen bitmap); the fade race and the off-main mask are fixed; new tests pin the overlay panel rules, SwiftUI's Sway green, and the badge cut-out |
| User report (2026-10-25) | Fixed, needs the user's check | Every Terminal window came forward when Sway focused one. A probe on the user's Mac showed `NSRunningApplication.activate(options: [])` from a background process brings only the app's front window, so the cause was the `AXFrontmost` call. Now: raise + main, then activation (`.appActivation`); `AXFrontmost` only as the fallback (`.accessibilityFrontmost`). SPEC D42, CONTRACT §6.7 steps 4–5 |
| Verification, PR, CI | Running | Full `xcodebuild test`: 1077 tests, zero warnings; lint and guard clean |

## Builder agents

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-ui-m6 | `SwayUI` | Theme and accent, menu bar icon, welcome step, edge glow, Focus Lock notice, motion, Appearance settings (CONTRACT §6.5.4; issues #28–#32) | Sonnet | **Done** | 583 SwayUI tests (89 new, none regressed); lint and guard clean. Accepted interpretations: the menu bar mark is fitted to a 15 pt area by its visual bounds (mapping the whole 100-unit square would make it 9 pt wide); `Harness.openSetup()` presses Get Started on the welcome; the notice shows on the main display when tracking is off. **Orchestrator change:** the asset-catalog accent color is removed, because under macOS's Multicolor setting it showed through and "Match macOS" still looked green (the builder flagged it) |

### Earlier phases (done)

M4 + M5: builder-system (`SystemIntegration`), builder-ui-m4, builder-ui-m5, and an Opus review (six findings, all
fixed) — PR #47. M2 + M3: builder-engine, builder-focus, builder-pose, builder-ui — PR #45.

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
