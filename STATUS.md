# Status

Phase: **M0 + M1** (stop at the M1 go/no-go gate). Updated by the orchestrator.

## Orchestrator tasks

| Task | Status | Notes |
|---|---|---|
| Read PLAN.md, clarify, write SPEC/CONTRACT/STATUS | Done | Answers: 2-display MVP with generic-N internals; stop after M1; full GitHub setup |
| Skeleton: Xcode project, SwayCore package, SwayModels, stubs | Done | `swift build`/`swift test` (12 tests) and unsigned `xcodebuild build`/`test` pass; lint and privacy guard clean |
| User approval of Phase 1 | **Waiting** | |
| GitHub M0: create private repo, push, labels, milestones, issues | Pending approval | `scripts/seed-github.sh` |
| Integrate modules into app target | Not started | |
| Review pass (Opus) | Not started | |

## Builder agents (Phase 2)

| Agent | Module | Task | Model | Status | Report |
|---|---|---|---|---|---|
| builder-camera | `CameraService` | Capture, device selection, permission, sleep/lock suspend (CONTRACT 6.1) | Sonnet | Not started | |
| builder-pose | `PoseEstimator` | Vision pose + landmark proxy, `LivePoseSource` (CONTRACT 6.2) | Sonnet | Not started | |
| builder-traces | `PoseTraces` | Store, replay, synthetic, separability analysis, Markdown (CONTRACT 6.3) | Sonnet | Not started | |
| builder-displays | `DisplayTracker` | NSScreen layout + change stream (CONTRACT 6.4) | Sonnet | Not started | |
| builder-ui | `SwayUI` | AppModel, menu bar, debug window, gate test + overlay, report (CONTRACT 6.5) | Sonnet | Not started | |
| reviewer | all | Contract conformance, full xcodebuild, warnings, tests, integration fixes | Opus | Not started | |

## Open issues

- xcode-select points at Command Line Tools; all commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (user step: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).
- Signed builds need a one-time keychain approval for `codesign` (user step, in Xcode).
