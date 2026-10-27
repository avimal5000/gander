# Sway: Engineering Contract (phase M7)

Builders follow this document exactly. SPEC.md says *what* to build; this file says *where and how*. PLAN.md
is background only. If anything here is wrong or missing, **stop and report**. Do not invent your own version.

## 0. Rules for every builder

1. Edit only files inside your own module:
   - `SwayCore/Sources/<Module>/`
   - `SwayCore/Tests/<Module>Tests/`
2. Never touch any of these (the orchestrator owns them):
   - `SwayModels`, `Package.swift`
   - the `Sway/` app target, `Sway.xcodeproj`, `Config/`
   - `scripts/`, `.github/`, or any root document
3. Replace the orchestrator's stub files in your module. Keep every public name and signature listed in your
   section of §6.
4. Make nothing public beyond what §6 lists. Everything else is `internal`, and tests use `@testable import`.
5. Verify only with the isolated commands in §4, never a full `xcodebuild`.
6. If the contract blocks you (a missing type, a wrong signature, an impossible requirement), stop. Report the
   problem and the exact change you propose.
7. Finish with a report: what you built, files created, test results (pasted summary), open issues, and
   assumptions.

## 1. Repository layout

```
Sway/                          repo root
├── PLAN.md  SPEC.md  CONTRACT.md  STATUS.md  README.md
├── Sway.xcodeproj/            orchestrator only (synchronized folder group, shared scheme "Sway")
├── Sway/                      app target sources: SwayApp.swift, AppComposition.swift, Assets.xcassets
├── Config/Sway.entitlements   orchestrator only
├── SwayCore/                  local Swift package "SwayCore" (one library product "SwayCore")
│   ├── Package.swift          orchestrator only
│   ├── Sources/<Module>/
│   └── Tests/<Module>Tests/
├── scripts/                   privacy-guard.sh, lint.sh, seed-github.sh
├── docs/decisions/            decision records (M1 gate)
└── .github/                   CI, templates, dependabot
```

## 2. Modules and ownership

| Module | Owner | Purpose (M1) | Frameworks allowed |
|---|---|---|---|
| `SwayModels` | orchestrator | Shared value types, protocols, policy constants, logging | Foundation, CoreGraphics, CoreVideo, os |
| `CameraService` | builder-camera | AVFoundation capture, device selection, permission, sleep/lock suspend | + AVFoundation, CoreMedia, AppKit (NSWorkspace notifications only) |
| `PoseEstimator` | builder-pose | Vision head pose + landmark proxy; `LivePoseSource` | + Vision, CoreVideo, CoreMedia |
| `PoseTraces` | builder-traces | Trace persistence, replay/synthetic sources, separability analysis, Markdown summary | Foundation only (+ os) |
| `DisplayTracker` | builder-displays | NSScreen layout, stable IDs, change stream | + AppKit, CoreGraphics |
| `SwayUI` | builder-ui | `AppModel`, all scenes and views, gate test flow, overlays, switch preview, Focus Test window | + SwiftUI, AppKit, Charts, Observation |
| `SwitchEngine` (M2) | builder-engine | Calibration profile fitting, pose classification, switch state machine | Foundation only (+ os) |
| `FocusControl` (M3) | builder-focus | Last-used window per display, focus switching via Accessibility | + AppKit, ApplicationServices, CoreGraphics |
| `SystemIntegration` (M4) | builder-system | Global shortcut (Carbon hot key) and the login item | + AppKit, Carbon, ServiceManagement |

PLAN.md's `CalibrationModel` and `SwitchDecider` live together in `SwitchEngine`, so the engine-level tests over
recorded traces can exercise both without a cross-module import. Its `WindowTracker` and `FocusController` live
together in `FocusControl` for the same reason.

M4 + M5 keep the tracking loop, settings, and setup inside `SwayUI` (they are `AppModel` state and its pure
helpers), and put the two system services (global shortcut, login item) in `SystemIntegration`. The `SwaySettings`
and `TrackingPipeline` modules planned earlier are not created.

## 3. Dependency rules

- Every feature module depends **only** on `SwayModels`, plus Apple system frameworks from the table above.
- No module imports another feature module. Cross-module collaboration goes through `SwayModels` protocols,
  and the app target injects concrete types (§7).
- Zero third-party dependencies. No networking frameworks (§11).

## 4. Build and test commands

The Command Line Tools toolchain cannot run `swift test` on this machine, so always set `DEVELOPER_DIR`.
`SWAY_MODULE` makes the manifest declare only `SwayModels` plus your module, which isolates you from
siblings that are mid-edit. The per-module scratch path stops parallel builds from blocking each other.

**Never keep the repo or its build products in an iCloud-synced folder** (for example `~/Documents` or
`~/Desktop`). The File Provider adds extended attributes that make codesign reject test bundles ("resource
fork, Finder information, or similar detritus not allowed"). The repo lives in `~/Developer/Sway` for this
reason. The scratch paths below are inside the repo and gitignored (`.build-*/`).

```bash
cd /Users/avimalhotra/Developer/Sway/SwayCore
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SWAY_MODULE=<Module> swift build --scratch-path .build-agents/<Module>
SWAY_MODULE=<Module> swift test  --scratch-path .build-agents/<Module>
# full package / app (reviewer, orchestrator):
swift test
xcodebuild -project ../Sway.xcodeproj -scheme Sway -derivedDataPath ../.build-xcode test CODE_SIGNING_ALLOWED=NO
# format + lint your own files (config: /Users/avimalhotra/Developer/Sway/.swift-format)
xcrun swift-format format --in-place --recursive Sources/<Module> Tests/<Module>Tests
xcrun swift-format lint --strict --recursive Sources/<Module> Tests/<Module>Tests
```

Done means:
- build: zero warnings and zero errors in your module;
- test: all tests pass;
- lint: clean;
- `../scripts/privacy-guard.sh` passes.

## 5. Shared types (`SwayModels`)

The source files in `SwayCore/Sources/SwayModels/` are the definitive API. Read them all before coding.

| File | Contents |
|---|---|
| `HeadPose.swift` | `HeadPose`, `PoseSample` |
| `Camera.swift` | `CameraDevice`, `CameraAuthorization`, `CameraError`, `SuspendReason`, `CaptureStatus`, `CameraFrame`, protocol `FrameSource` |
| `PoseSource.swift` | `PoseSourceConfiguration` (incl. `includeLandmarks`, M2), `PoseSourceEvent`, protocol `PoseSource`, protocol `PoseEstimating` (`estimate(_:includeLandmarks:)`) |
| `Displays.swift` | `DisplayID`, `DisplayInfo`, `DisplayLayout` (sorting + fingerprint), protocol `DisplayProviding` (`@MainActor`) |
| `Traces.swift` | `TraceSegment`, `PoseTrace`, `TraceStoreError`, protocol `TraceStoring` |
| `Separability.swift` | `PoseFeatureSet`, `DisplayPoseStats`, `PairSeparation`, `GateVerdict`, `GateThresholds`, `SeparabilityReport`, `GateAnalysis`, `DisplayClassification`, protocol `SeparabilityAnalyzing` |
| `SwayPolicy.swift` | `SwayPolicy` constants, `SwayLog.logger(category:)` |
| `Switching.swift` (M2) | `DisplayProfile`, `CalibrationProfile`, `CalibrationError`, `PoseClassification`, `SwitchSettings`, `SwitchContext`, `SwitchPhase`, `SwitchHoldReason`, `SwitchDecision`, protocols `SwitchDeciding`, `SwitchEngineMaking` |
| `Focus.swift` (M3) | `WindowSummary`, `FocusMethod`, `FocusResult`, protocol `FocusControlling` |
| `CalibrationLibrary.swift` (M5) | `CalibrationKey`, `CalibrationMatch`, `CalibrationLibrary`; `CalibrationProfile.key`, `.displayIDs`, `.restricted(to:)` |
| `SwitchSensitivity.swift` (M5, 0.1.x) | `SwitchSensitivity` (hold time, confidence level, and pause after a switch → `SwitchSettings`) |
| `SystemIntegration.swift` (M4, M5) | `HotKeyShortcut`, `HotKeyAction`, `HotKeyError`, protocol `HotKeyRegistering`; `LoginItemStatus`, `LoginItemError`, protocol `LoginItemControlling` |

`SwayPolicy.maxTrackedDisplays` is now 3 (SPEC D22).

Semantics that the code cannot express:
- **Angles** are degrees everywhere. Vision gives radians, so convert in `PoseEstimator`.
- **Timestamps** are seconds on a monotonic clock; only differences matter. Live sources use the sample
  buffer's presentation time.
- **`CameraFrame.pixelBuffer`** must not be retained past the frame handler call, and must never be copied
  to disk or to any image type that is persisted.
- **`DisplayLayout.init(displays:)`** sorts the displays and computes the fingerprint itself. Always build
  layouts through it.

## 6. Module contracts

### 6.1 `CameraService` (builder-camera)

**Public API (exact):**
```swift
public final class CameraCaptureService: FrameSource {   // may be @unchecked Sendable with justification
    public init()
    // + the FrameSource requirements
}
```

**Behavior:**
- **Discovery.** Use `AVCaptureDevice.DiscoverySession` with device types `[.builtInWideAngleCamera,
  .external, .continuityCamera]`, media `.video`, position `.unspecified`. Set `isBuiltIn` when
  `deviceType == .builtInWideAngleCamera`.
- **Selection** (a pure internal function, unit-tested): use the preferred ID if it is connected, else the
  first built-in device, else `AVCaptureDevice.default(for: .video)`. With no device at all, throw
  `CameraError.noDevice`. An unknown preferred ID falls back silently (log at `.info`).
- **`resolvedDevice(for:)`** (M4 review fix, a `FrameSource` requirement with a default for fakes): the device the
  selection rule picks right now, or `nil`. Lists devices only; never touches the camera or prompts.
- **Authorization.** `authorizationStatus()` maps `AVCaptureDevice.authorizationStatus(for: .video)`.
  `requestAuthorization()` calls `requestAccess` only when the status is `.notDetermined`. `start` never
  prompts; it throws `.notAuthorized` unless already authorized.
- **Session.** All session work runs on a private serial queue.
  - Format: preset `.vga640x480` if the device supports it, else the smallest format at least 640×480 wide,
    else the device default.
  - Frame rate: lock the device and set min/max frame duration to `1/frameRate`, clamped into a supported
    `AVFrameRateRange`. The clamping is a pure tested helper.
  - Output: `AVCaptureVideoDataOutput` with `alwaysDiscardsLateVideoFrames = true` and pixel format
    `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`. Its delegate runs on a private serial frame queue.
    Each frame becomes `CameraFrame(pixelBuffer:timestamp:)` and goes to `frameHandler`.
  - No other outputs: no photo, movie, or asset writer, and no preview layer.
- **Status sequence.** `.starting` → `.running(device)`. If `AVCaptureSessionRuntimeError` fires, retry
  once, then report `.failed(.runtimeFailure(msg))`.
- **Disconnects and interruptions.**
  - Device disconnected (`AVCaptureDevice.wasDisconnectedNotification`): report `.interrupted("Camera
    disconnected")`. When a device with the same ID reconnects, restart.
  - Session interrupted, device in use by another app, or **no frames for 3 s while running** (a frame
    watchdog): report `.interrupted(reason)` and keep trying. When frames resume, report `.running(device)`.
- **Suspend and resume** (PLAN.md privacy guarantee). Keep a set of active `SuspendReason`s:
  - `NSWorkspace.willSleepNotification` → `.systemSleep`, cleared by `didWakeNotification`.
  - `screensDidSleepNotification` → `.displaysAsleep`, cleared by `screensDidWakeNotification`.
  - `DistributedNotificationCenter` `"com.apple.screenIsLocked"` → `.screenLocked`, cleared by
    `"com.apple.screenIsUnlocked"`.

  When the set becomes non-empty, tear the session down completely (stop running, remove inputs) so the
  camera light goes off, and emit `.suspended(firstReason)`. When it becomes empty again and the caller has
  not called `stop()`, rebuild the session and emit `.starting` then `.running`. Keep this logic in a pure,
  tested type.
- **`stop()`.** Stops the session, removes inputs and outputs, emits `.stopped`, drops the handlers,
  removes the observers, and is idempotent.
- **Logging.** `SwayLog.logger(category: "camera")`. Never log frame data.

**Tests** must never touch real devices, permission APIs, or sessions. Cover:
- the selection rule over fake device lists;
- frame-rate clamping;
- suspend/resume reason-set transitions;
- the authorization status mapping.

#### 6.1.1 M7 additions to `CameraService` (builder-camera-m7)

No public API change. Everything here is internal to `CameraService` (SPEC D43, D47).

1. **Suspension is sticky (replaces the "Suspend and resume" rules above where they differ).**
   - `SuspendTracker` records `begin` and `end` for every reason whether or not capture is requested.
     `captureStopped()` sets `isCaptureRequested = false` but **keeps** the active reasons.
     `captureRequested()` returns `.suspend(first)` when any reason is active, else `.resume`.
     `begin`/`end` while capture is not requested update the set and return `.none`. After `captureStopped()`
     nothing resumes capture, because `end` returns `.none` when capture is not requested.
   - The system observers are installed once, when the controller is created, and removed only on `deinit`.
     `stop()` and `shutdown()` no longer remove them.
   - When the observers are installed, seed `.displaysAsleep` if the main display is asleep. The check is an injected
     `@Sendable () -> Bool` (live: `CGDisplayIsAsleep(CGMainDisplayID()) != 0`), so tests never touch displays.
   - New reason `.sessionInactive`: `NSWorkspace.sessionDidResignActiveNotification` begins it and
     `sessionDidBecomeActiveNotification` ends it. When the observers are installed, also seed it if this session is not
     the console session (an injected `@Sendable () -> Bool`; live:
     `CGSessionCopyCurrentDictionary()` has `kCGSessionOnConsoleKey` false).
   - **Lock and unlock are delivered immediately (review fix).** `DistributedNotificationCenter` suspends delivery to an
     inactive app and coalesces what it queues, and Sway is almost never the active app. Register the
     `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` observers with `addObserver(_:selector:name:object:
     suspensionBehavior: .deliverImmediately)` (a small `NSObject` that hops to the controller's queue). Make the
     registration an injected closure in `CaptureEnvironment`, so tests keep using a plain notification center.
   - **Self-heal.** On `didWake`, `screensDidWake`, `screenIsUnlocked`, and `sessionDidBecomeActive`, after clearing
     the event's own reason, also clear `.displaysAsleep` if the injected check says the main display is awake (a
     missed `screensDidWake` must not leave capture suspended).
   - Tests: a reason begun before stop and still active at the next `start` gives `.suspend`; an `end` arriving while
     stopped clears the reason and still resumes nothing; the display seed; `.sessionInactive`; the self-heal.
2. **Retry backoff (D47).** A pure `RetryBackoff` type, tested:
   - After a failure to find or open the device: delays 1 s, 2 s, 5 s, then 10 s for every later try.
   - After a stall rebuild that did not bring frames back: 10 s, 30 s, then 60 s for every later try.
   - Any run of frames resets both sequences. The one-time retry after a runtime error is unchanged.
3. **Center Stage off (D47).** Before the first session starts, set `AVCaptureDevice.centerStageControlMode = .app`
   and `AVCaptureDevice.isCenterStageEnabled = false`, once per process, from a small injectable function so tests
   never touch it.

### 6.2 `PoseEstimator` (builder-pose)

**Public API (exact):**
```swift
public final class VisionPoseEstimator: PoseEstimating { public init() }
public final class LivePoseSource: PoseSource {
    public init(frameSource: any FrameSource, estimator: any PoseEstimating)
}
```

**`VisionPoseEstimator.estimate(_:includeLandmarks:)`:**
1. Create a `VNImageRequestHandler(cvPixelBuffer:orientation: .up, options: [:])`. Run
   `VNDetectFaceRectanglesRequest` (revision 3 or the latest available; it provides roll, yaw, and pitch)
   and pick the observation with the largest bounding-box area. No face → `nil`.
2. **Only when `includeLandmarks` is true** (M2, SPEC D15): run `VNDetectFaceLandmarksRequest` on the same
   handler with `inputFaceObservations = [largest]`. When false, no landmark request runs and `landmarkYaw` /
   `landmarkPitch` are `nil`.
3. Fill `HeadPose`:
   - `yaw`, `pitch`, `roll`: radians to degrees. If pitch is `nil`, use 0 and log once.
   - `faceConfidence`: the observation's confidence.
   - `faceBounds`: the bounding box.
   - `landmarkYaw` and `landmarkPitch`: from a **pure, unit-tested** geometry function over landmark points
     (normalized to the face box). It uses the eye centers (always eye-region centroids, never pupils:
     pupils move with gaze, and PLAN.md defers eye gaze) and the nose tip (from `nose` / `noseCrest`). The result must be continuous, about 0 when facing the
     camera, and monotonic with rotation. Document the exact formula in a doc comment. If either landmark
     region is missing, both are `nil`.
4. Must be safe to call from one serial queue at a time. Vision objects are not shared across threads
   unsafely. Do not retain the pixel buffer.
5. Target under 30 ms per 640×480 frame. Never write images.

**`LivePoseSource`:**
- `start(_:)`:
  1. If running, `stop()` first so the previous stream finishes.
  2. If `frameSource.authorizationStatus() != .authorized`, throw `CameraError.notAuthorized`. Never prompt.
  3. Create an `AsyncStream<PoseSourceEvent>` with `bufferingPolicy: .bufferingNewest(64)` and yield
     `.status(.starting)`.
  4. Call `frameSource.start(deviceID: configuration.cameraDeviceID, frameRate: configuration.frameRate,
     ...)`. The frame handler runs the estimator synchronously, passing `configuration.includeLandmarks`, and
     yields
     `.sample(PoseSample(timestamp: frame.timestamp, pose: estimate))`. The status handler yields
     `.status(status)`.
  5. If `frameSource.start` throws: yield `.status(.failed(error))` (map non-`CameraError` errors to
     `.configurationFailed`), finish the stream, and rethrow.
- `stop()`: calls `await frameSource.stop()`, yields `.status(.stopped)`, finishes the stream. Idempotent.
- **Consumer cancellation.** If the consumer stops iterating (`onTermination`), the source must stop
  capture. This is a privacy requirement.
- Thread-safe (`OSAllocatedUnfairLock` or an actor-backed core; see §8).
- **Tests:**
  - event order using a fake `FrameSource` that emits frames from a `CVPixelBufferCreate` buffer, and a
    fake estimator;
  - `stop()` finishes the stream;
  - a second `start()` finishes the first stream;
  - `.notAuthorized` throws and the frame source is never started;
  - consumer cancellation stops the frame source;
  - the landmark geometry function;
  - Vision on a blank 640×480 buffer returns `nil` without crashing (these real-Vision tests skip when `CI` is
    set; GitHub's virtual Macs hang in Vision);
  - (M2) `LivePoseSource` passes `includeLandmarks` from the configuration to the estimator, both values, and a
    restart with a different value uses the new one;
  - (M2) with `includeLandmarks: false` the estimator never creates a landmark request (factor the request plan
    into a small pure helper that returns which requests to run, and test that).

#### 6.2.1 M7 additions to `PoseEstimator` (builder-pose-m7): adaptive frame rate (SPEC D45)

`LivePoseSource` gains `setDemand(_:)` (the `PoseSource` requirement in `SwayModels`) and one defaulted init
parameter. Source-compatible with every existing call:
```swift
public init(
    frameSource: any FrameSource, estimator: any PoseEstimating,
    isPowerConstrained: @escaping @Sendable () -> Bool = LivePoseSource.systemPowerConstrained)
```
`systemPowerConstrained` is true when `ProcessInfo.processInfo.isLowPowerModeEnabled` or the thermal state is
`.serious` or `.critical`. `LivePoseSource` reads it at most once per second of frame time, never per frame.

**`AdaptiveFrameRate`** (internal, pure, `Sendable`, `Equatable`, no clock of its own: it works on frame timestamps in
seconds):
- State: `demand` (default `.full`), `isPowerConstrained`, the time of the last processed frame, and the time a face
  was last seen (a start counts as a face just seen).
- `mutating func shouldProcess(frameAt t: TimeInterval) -> Bool`, `mutating func record(face: Bool, at t:
  TimeInterval)`, `mutating func setDemand(_:)`, `mutating func setPowerConstrained(_:)`, `mutating func reset()`.
- The minimum interval between processed frames:

| Demand | No power constraint | Power constrained |
|---|---|---|
| `.full` | 1/15 s, always | 1/15 s |
| `.adaptive`, face seen within 2 s | 1/15 s | 1/10 s |
| `.adaptive`, no face for 2 s or more | 1/5 s | 1/2 s |
| `.reduced` | 1/5 s | 1/2 s |

- **The intervals are averages kept on a nominal schedule** (review fix: measuring each interval from the last
  processed frame's real time rounds the rate down to the camera's frame grid, so 1/10 s on a 15 fps camera gave 7.5
  fps and a 20 fps camera gave 10). The struct keeps a `slot`: the time the last processed frame was due. A frame is
  processed when `t >= slot + interval - 0.004` (jitter tolerance). After processing, `slot = max(slot + interval,
  t - interval / 2)`: it stays on the grid, and re-anchors when the frame came far behind. Results: a 15 fps camera
  gives exactly 10 fps for 1/10 s (gaps alternate one and two frames, so one missed sample leaves 0.2 s, under the
  decider's 0.25 s `maxGap`); 20, 24, and 30 fps cameras give 15 fps for 1/15 s; ±5 ms timestamp jitter does not drop
  frames. A timestamp earlier than `slot`, and the first frame after a `reset()`, are processed and set `slot = t`.
- A processed frame with a face makes the very next frame eligible at the active interval (the face-seen time
  updates, so the rate is back to active at once). `setDemand` to a higher rate takes effect on the next frame.
- Frames that are not processed are dropped before the estimator runs and yield nothing. Never retain their buffers.

**`LivePoseSource`** asks the struct before every `estimate`, records the result after, resets it on `start`, and
applies `setDemand` under its lock. The default demand after `start` is `.full`.
Result: a hard 15 fps cap whatever the device delivers; the switching speed with a face present is unchanged.

**Tests:** every table row, boundary and tolerance, timestamps going backwards, the 2 s absent boundary, the instant
return on a face, `reset()`, `setDemand` mid-stream; `LivePoseSource` with `FakeFrameSource` and `FakePoseEstimator`:
estimator calls drop to one per 5 fps interval after 2 s without a face and return to every frame at 15 fps on the
first face, a 30 fps input is processed at 15 fps, `setDemand(.reduced)` lowers the rate, power-constrained changes
intervals, `start` resets. Plus a new test file in `SwitchEngineTests` (SwayModels and SwitchEngine only) that feeds
the decider a face-then-absent-then-face scenario at the throttled sample times and checks the switch still fires
at the dwell plus at most one frame interval after the first qualifying sample, and that a switch after an absent
period fires within 1 s plus the dwell of the face returning.

### 6.3 `PoseTraces` (builder-traces)

**Public API (exact):**
```swift
public struct FileTraceStore: TraceStoring { public init(directory: URL? = nil) }   // nil → default folder
public struct SeparabilityAnalyzer: SeparabilityAnalyzing { public init() }
public final class ReplayPoseSource: PoseSource {
    public init(trace: PoseTrace, speed: Double = 1.0)
}
public struct SyntheticCluster: Sendable, Equatable {
    public var displayID: DisplayID; public var yaw: Double; public var pitch: Double
    public init(displayID: DisplayID, yaw: Double, pitch: Double)
}
public enum SyntheticTraces {
    public static func gateTrace(clusters: [SyntheticCluster], std: Double, samplesPerSegment: Int,
                                 rounds: Int, faceDropRate: Double = 0,
                                 frameRate: Double = SwayPolicy.defaultFrameRate, seed: UInt64) -> PoseTrace
}
```

**`FileTraceStore`:**
- Default folder: `URL.applicationSupportDirectory/Sway/Traces`.
- JSON format: `.prettyPrinted` and `.sortedKeys`, ISO-8601 dates.
- `save`:
  - creates the folder if needed;
  - file name `yyyyMMdd-HHmmss-<first 8 chars of id, lowercased>.json`, local time, `en_US_POSIX`;
  - atomic write;
  - in non-`DEBUG` builds (`#if !DEBUG`) writes nothing and throws `.disabledInReleaseBuilds`.
- `load`: works in every build configuration. Map errors to `.io` or `.decoding`.
- `list`: `.json` files, sorted by file name descending (newest first). Returns `[]` if the folder is missing.

**`ReplayPoseSource`:**
- Emits `.status(.starting)`, then `.status(.running(nil))`, then every sample of every segment in array
  order, then `.status(.stopped)`, then finishes.
- Pacing: sleep each timestamp delta divided by `speed`. `speed <= 0` means no delay.
- `stop()` cancels the run and finishes the stream. Restart semantics match `PoseSource`.

**`SyntheticTraces.gateTrace`** must be deterministic for a given seed:
- Implement a SplitMix64 PRNG and Box–Muller Gaussian sampling. Do not use `SystemRandomNumberGenerator`.
- For each round `1...rounds` and each cluster in order, add one segment `(displayID, round)` of
  `samplesPerSegment` samples. Timestamps advance by `1/frameRate` continuously across segments.
- Pose values:
  - `yaw ~ N(cluster.yaw, std)`, `pitch ~ N(cluster.pitch, std)`, `roll ~ N(0, 1)`;
  - `faceConfidence` 0.95 and a plausible centered `faceBounds`;
  - `landmarkYaw = 0.9·yaw + N(0, std/2)`, `landmarkPitch = 0.9·pitch + N(0, std/2)`.
- A `faceDropRate` fraction of samples, chosen by the PRNG, get `pose = nil`.
- `layout`: one `DisplayInfo` per cluster, 1920×1080, placed left to right. `name = "Display <n>"`,
  `cameraName = "Synthetic"`.

**`SeparabilityAnalyzer.analyze`.** These rules are normative; implement them exactly. For each
`PoseFeatureSet` in `allCases` order:

1. **Labeled data.** Use segments with a non-nil `displayID`. Group them by display in order of first
   appearance. Take each display's name from `trace.layout?.display(withID:)?.name`, falling back to the
   ID's raw value.
2. **Points.**
   - `visionAngles`: `(yaw, pitch)` for every sample with a pose.
   - `landmarkAngles`: `(landmarkYaw, landmarkPitch)` for samples where both are non-nil.
   - `frameCount` = all samples in that display's segments; `faceCount` = number of points.
   - `meanX/Y` are means. `stdX/Y` are sample standard deviations (n−1), or 0 when n < 2.
3. **Pairs.** Every unordered pair (i < j) in display order.
   - `meanDistance = ‖μi − μj‖`. If it is 0, `dPrime = 0`.
   - Otherwise let `u = (μi − μj)/‖μi − μj‖` and let Σ be the 2×2 sample covariance (n−1) of each class.
     Compute `σ² = max(uᵀ Σ u, minStd²)` per class, then `dPrime = meanDistance / sqrt((σi² + σj²)/2)`.
4. **Classifier** (also used by `classify`).
   - The normalized distance to a display is `z = sqrt(((x − meanX)/sX)² + ((y − meanY)/sY)²)`, with
     `sX = max(stdX, minStd)` and likewise `sY`.
   - The display with the smallest `z` wins. Ties go to the earlier display.
5. **Accuracy.**
   - If the labeled segments contain at least 2 distinct `round` values, use leave-one-round-out. For each
     round r, compute centroids and stds from the points of the other rounds and classify the points of
     round r. A display with no training points in a fold is not a candidate, and its test points count as
     wrong.
   - With a single round, split each segment's points in time order: the first ⌊n/2⌋ train, the rest test.
   - `accuracy = correct / total` test points. It is `nil` when the data is insufficient (step 6) or there
     are no test points.
6. **Verdict.**
   - `insufficientData` if there are fewer than 2 labeled displays or any display has
     `faceCount < minFaceSamplesPerDisplay`.
   - `go` if every pair has `dPrime ≥ goDPrime`, `accuracy ≥ goAccuracy`, and every display has
     `faceDetectionRate ≥ goFaceDetectionRate`.
   - `marginal` under the same three checks with the marginal thresholds.
   - `noGo` otherwise.
7. **Notes.** Plain sentences:
   - the weakest pair and its d′;
   - any display below the face-rate thresholds;
   - for `landmarkAngles`, the share of face frames that lacked landmarks.

`overall` is the maximum verdict. `bestFeatureSet` is the argmax verdict; ties go to higher accuracy (`nil`
counts as −1), then `allCases` order. `classify(_:using:)` applies step 4 to the `report.displays` with `faceCount > 0`. A display without face
samples is not a candidate, as in step 5. It uses `minStd = GateThresholds.default.minStd`, returns `nil` when
the pose lacks the report's features or no display is a candidate, and sets `runnerUpDistance` to `nil` when
there is only one candidate.

**`markdownSummary`:**
- Opens with `## M1 head-pose gate result`.
- Bullets: date (local, `yyyy-MM-dd HH:mm`), camera, displays (`name (WxH pt[, built-in])`), overall
  verdict in bold with the best feature set, thresholds.
- Then for each feature set: a `### <Feature set title> — <VERDICT>` heading, a display table (Display |
  Frames | Face % | Mean yaw | Mean pitch | Std yaw | Std pitch), a pair table (Pair | Mean distance | d′),
  the accuracy as a percentage with one decimal, and the notes.
- Numbers use one decimal.

**Tests:**
- well-separated synthetic clusters → `go`;
- overlapping clusters → `noGo`;
- too few samples → `insufficientData`;
- high `faceDropRate` lowers the verdict through the face-rate checks;
- d′ matches a hand-computed case;
- leave-one-round-out and the split path both run;
- `classify` picks the nearest cluster;
- the store round-trips in a temp folder (DEBUG), and `list` order is correct;
- replay emits everything in order at `speed: 0`;
- synthetic traces are deterministic for a given seed;
- the Markdown output contains the verdict and tables.

### 6.4 `DisplayTracker` (builder-displays)

**Public API (exact):**
```swift
@MainActor public final class ScreenDisplayTracker: DisplayProviding { public init() }
```

**Behavior:**
- `currentLayout` is built from `NSScreen.screens`. For each screen:
  - `cgDisplayID` comes from `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`;
  - the ID comes from `CGDisplayCreateUUIDFromDisplayID` + `CFUUIDCreateString`, falling back to
    `"cg-<cgDisplayID>"`;
  - `name = localizedName`, `frame = screen.frame`;
  - `isBuiltIn = CGDisplayIsBuiltin(id) != 0`, `isMain = CGDisplayIsMain(id) != 0`.

  Always build through `DisplayLayout(displays:)`. Keep the screen-to-`DisplayInfo` mapping in a pure helper
  over a plain descriptor struct, so it is testable without NSScreen.
- `layouts()` returns a new stream per call that yields the current layout immediately. It observes
  `NSApplication.didChangeScreenParametersNotification`, debounces 0.5 s, recomputes, and yields only when
  the layout differs from the last one yielded on that stream. On termination it removes its observers.
- Log category `"displays"`.

**Tests:** the descriptor-to-`DisplayInfo` mapping, the UUID fallback, dedupe and debounce logic (with an
injectable clock or scheduler), and that `layouts()` yields at least one value. Never assert on the number
of real screens.

### 6.5 `SwayUI` (builder-ui)

**Public API (exact):**
```swift
@MainActor @Observable public final class AppModel {
    public init(camera: any FrameSource, poseSource: any PoseSource, displays: any DisplayProviding,
                traceStore: any TraceStoring, analyzer: any SeparabilityAnalyzing,
                defaults: UserDefaults = .standard)
}
public struct SwayScenes: Scene { public init(model: AppModel) }
```
Everything else is internal and up to you, within SPEC.md F1–F9.

**Scenes:**
- **`MenuBarExtra`** with `.menuBarExtraStyle(.window)`. Its label is an SF Symbol for the state:
  - off: `eye.slash`
  - starting: `eye`
  - running with a face: `eye.fill`
  - running without a face: `eye.trianglebadge.exclamationmark`
  - suspended: `pause.circle`
  - interrupted or failed: `exclamationmark.triangle`

  Content per F1.
- **`Window("Pose Debug", id: "pose-debug")`** per F5/F6.
- **`Window("Head-Pose Gate Test", id: "gate-test")`** per F7–F9.

  When opening a window from the menu bar, call `NSApp.activate()` so it comes to the front (LSUIElement
  app).

**`AppModel` responsibilities:**
- Start and stop `poseSource` with `PoseSourceConfiguration(cameraDeviceID: selectedCameraID)`, consuming
  its stream in a `Task`.
- Track: latest sample, status, measured fps (samples per second over the last 2 s), a rolling 10 s history
  for plots, camera devices, authorization, layout (from `displays.layouts()`), the latest `GateAnalysis`
  plus its `PoseTrace`, and the live classification.
- Persist the selected camera in `defaults` under `"sway.cameraDeviceID"` (nil = default).
- Permission flow per F2: `camera.requestAuthorization()`. The deep link is
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`, opened via `NSWorkspace`.
- Stop the camera on `NSApplication.willTerminateNotification`.

**Gate flow:** a pure internal state machine (`GateTestSession` or similar) with an injected clock.
- Steps are rounds × displays in layout order, each with a settle phase (1.5 s) then a hold phase.
- Only hold-phase samples are recorded, as `TraceSegment(displayID:, round:, samples:)`. Include no-face
  samples.
- It supports cancel, and on completion builds a `PoseTrace` (camera name, layout, segments).
- `AppModel` drives it from the sample stream and a timer, runs `analyzer.analyze(_, thresholds: .default)`,
  and in DEBUG calls `traceStore.save`. Show the error if saving throws.

**Overlay (AppKit is allowed here):**
- One `NSPanel` per target screen: borderless, `.nonactivatingPanel`, level `.screenSaver`,
  `ignoresMouseEvents = true`, clear background.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, with the
  frame equal to `screen.frame`.
- It hosts SwiftUI: a forest-green border, a centered target dot, the prompt text, and the countdown or
  progress. Fade in and out over about 300 ms.
- Find the `NSScreen` for a `DisplayInfo` by matching `cgDisplayID` against `NSScreenNumber`.
- Esc cancels via a local key monitor or the gate window's cancel button.

**Palette** (internal `SwayPalette`): forest `#2F5D3A`, sage `#9CAF88`, ivory `#F6F3EA`, charcoal `#2B2B2B`.
Otherwise use system fonts and controls. The accent is Sway green or the system's, as the user chooses (§6.5.4).
Support light and dark mode.

**Charts:** Swift Charts (system framework) or `Canvas`. Show no video and no camera preview (SPEC D9).

**Tests (no real camera or screens):**
- gate session sequencing, phase timing, labeling, cancel, and trace assembly;
- `AppModel` with fakes for every protocol: start/stop updates the status, events update the latest
  pose/fps, the permission-denied path, and the gate run producing an analysis via a fake analyzer;
- camera selection persistence via a `UserDefaults(suiteName:)` test suite.

Add `#Preview`s with fake dependencies where useful. Fakes live in the test target or in `#if DEBUG`
internal files.

#### 6.5.1 M2 + M3 additions to `SwayUI` (builder-ui)

**Public API change (exact):**
```swift
@MainActor @Observable public final class AppModel {
    public init(camera: any FrameSource, poseSource: any PoseSource, displays: any DisplayProviding,
                traceStore: any TraceStoring, analyzer: any SeparabilityAnalyzing,
                engine: any SwitchEngineMaking, focus: any FocusControlling,
                defaults: UserDefaults = .standard)
}
```

**1. Landmarks only during the gate test (SPEC D15).**
- `PoseSourceConfiguration.includeLandmarks` is `true` exactly while a gate test needs the camera, including its
  camera-start phase, and `false` for Live.
- If a gate test starts while Live runs without landmarks, restart the pose source with landmarks through the
  existing reconcile-on-configuration-change path. When the gate ends, Live continues without landmarks.
- Landmark readouts show "—" when the value is `nil`. When the plot is set to landmark features and no sample
  has them, it shows "Landmark angles are computed only during the gate test."
- Live guess: classify with the best feature set's report. If that returns `nil` because the pose lacks those
  features, classify with the `.visionAngles` report.

**2. Calibration profile (SPEC F10, D17).**
- After every successful gate analysis and every opened trace, call
  `engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)`.
  - On success: store it as `calibrationProfile` and persist it as JSON (`JSONEncoder`, `.iso8601` dates) in
    `defaults` under `"sway.calibrationProfile"`.
  - On failure: keep the previous profile and show the error in the report view in plain words:
    - `tooFewDisplays`: "Not enough face samples on at least two displays to calibrate. Run the gate test with your
      face visible.";
    - `featuresMissing`: "This trace has no <feature set title>" (only possible for landmark angles).
- On launch, restore the stored profile. Ignore data that does not decode or has another `formatVersion`.
- `isCalibrationStale` is `!profile.matches(layout)` for the current layout.

**3. Switch preview (SPEC F11)** in the Pose Debug window, as a new "Switch preview" section.
- No profile: show "Not calibrated yet. Choose Calibrate… in the menu." (M5 wording; it was "Run the gate test to calibrate.")
- With a profile, while Live is on:
  - `AppModel` owns `decider: (any SwitchDeciding)?`, made with
    `engine.makeDecider(profile:settings: .default)` whenever the profile changes or Live starts.
  - Every live sample is processed with
    `SwitchContext(focusedDisplay: simulatedFocus, isFocusLocked: simulateFocusLock, targets: nil)`.
  - On `decision.switchTo = D`: set `simulatedFocus = D` and log it (newest first, at most 10 entries) with the
    wall-clock time, the display name, and the dwell latency. Latency is that sample's timestamp minus the
    timestamp of the sample that started the dwell; track it from the phase change `.idle` → `.dwelling`.
  - Reset the decider and set `simulatedFocus = nil` on a layout change, on a stream restart, and when the
    profile changes.
- Shown in the section:
  - the classification: nearest display name with a margin bar (0–1), or "No face" / "Looking elsewhere";
  - the phase: "Watching", "Dwelling on <name>" with a progress bar, or "Cooling down";
  - "Focus (simulated): <name or Unknown>";
  - a "Simulate Focus Lock" toggle;
  - a stale-calibration warning;
  - the log.
- Never call `focus.focus(...)` from the preview.

**4. Accessibility onboarding (SPEC F12),** at the top of the Focus Test window.
- Status "Accessibility: Granted" / "Not granted". While the window is visible, poll `focus.isTrusted()` every
  1 s using the model's injectable clock or timer, as in the gate flow.
- When not granted, show: "Sway needs Accessibility access to move keyboard focus to a window on the display you
  look at. It never moves the cursor and never reads window contents."
- "Grant Access…" calls `focus.requestTrust()`, then opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` through the existing
  system/desktop abstraction.

**5. Focus Test window (SPEC F13).** `Window("Focus Test", id: "focus-test")`, launch-guarded like the other
windows. The menu gets a "Focus Test Window…" item (SF Symbol `rectangle.2.swap`) after "Head-Pose Gate Test…".
- While visible, refresh every 1 s:
  - `focus.lastUsedWindows(in: layout)`;
  - `focus.focusedDisplay(in: layout)`.
- One row per display in layout order:
  - the display name, plus "(focused)" when it matches;
  - the last-used window: "App — Title", "App", or "No window";
  - **Focus**;
  - **Focus in 3 s**: shows a countdown, which can be cancelled.
- Run focus requests one at a time; ignore new presses while one is in flight.
- Log (newest first, at most 10), using the result:
  - "Focused <app> via Accessibility raise in <ms> ms";
  - "Focused <app> via app activation in <ms> ms";
  - "No window on <display>";
  - "Accessibility permission needed";
  - "Failed: <reason>".
- The buttons are disabled while not trusted.
- Never log or persist window titles (they are shown only).

**6. Tests** (fakes for `SwitchEngineMaking`, `SwitchDeciding`, and `FocusControlling` in the test target):
- the gate turns `includeLandmarks` on, and Live afterwards runs with it off;
- the live-guess fallback to Vision;
- a profile is fitted after an analysis and after an opened trace, persisted, restored, and its stale flag
  follows the layout;
- a fit failure keeps the old profile and shows the message;
- preview wiring:
  - a fake decider's switch updates the simulated focus and the log, with latency;
  - lock and layout changes reset it;
  - the preview never calls `focus`;
- Focus Test:
  - result texts;
  - the delayed focus fires after 3 s on the injected clock and can be cancelled;
  - one request at a time;
  - not trusted disables the buttons;
  - the trust poll runs only while visible;
- the onboarding button calls `requestTrust` and opens the deep link.

#### 6.5.2 M4 additions to `SwayUI` (builder-ui-m4)

**Public API change (exact):**
```swift
@MainActor @Observable public final class AppModel {
    public init(camera: any FrameSource, poseSource: any PoseSource, displays: any DisplayProviding,
                traceStore: any TraceStoring, analyzer: any SeparabilityAnalyzing,
                engine: any SwitchEngineMaking, focus: any FocusControlling,
                hotKeys: any HotKeyRegistering, loginItem: any LoginItemControlling,
                defaults: UserDefaults = .standard)
}
```
`loginItem` is only stored in M4; M5 uses it. New `UserDefaults` keys (all JSON with `.iso8601` dates unless noted):
`sway.calibrationLibrary`, `sway.trackingEnabled` (Bool), `sway.switchSensitivity`, `sway.focusLockShortcut`.

**1. Calibration library (SPEC D25).**
- `AppModel` keeps a `CalibrationLibrary`, persisted under `sway.calibrationLibrary` after every change.
- **Migration at launch:** if that key is absent and `sway.calibrationProfile` holds a profile that decodes with the
  current format version, start the library with it, persist the library, and remove the old key.
- **Active calibration:** `library.resolve(for: layout, cameraName: trackingCameraName)`, recomputed on launch, on a
  layout change, when the selected or running camera changes, and when the library changes.
  - `trackingCameraName` is `status.device?.name` while the camera runs. Otherwise it is the name of the camera
    capture would pick, asked of the camera service: `FrameSource.resolvedDevice(for: selectedCameraID)` (review
    fix: a guess made in `SwayUI` disagreed with capture's system-default fallback, which start-stop-looped the
    camera or stopped it at the first screen lock). It is refreshed with the device list, on a camera choice, and
    when AVFoundation posts a camera connect or disconnect (observed by notification name).
- Every successful fit (gate test, opened trace, and in M5 the Setup window) saves into the library instead of
  replacing a single profile. A failed fit keeps the library unchanged and shows the message as before.
- The single-profile staleness (`isCalibrationStale`) goes away: "no calibration fits" replaces it.

**2. Tracking switch (SPEC D23, D26, F18).**
- `liveEnabled` becomes `trackingEnabled`. The menu and the Pose Debug window show it as a **Tracking** switch.
- **Saved choice:** user actions (the switch, and in M5 "Start tracking") write `sway.trackingEnabled`. Automatic
  changes do **not** write it: a camera failure or an unexpected end of stream turning tracking off, and quitting
  (`applicationWillTerminate()`, `shutdown()`, `quit()`). So the next launch restores the user's choice.
- **Launch:** `init` reads the saved choice. When it is true, schedule one camera reconcile right after `init` (a
  `Task` on the main actor), so tracking starts without any window.
- `wantsCamera` is `gateRunState != .idle || (trackingEnabled && activeCalibration != nil && layout has at least 2
  displays)`. M5 adds the Setup window's camera steps.
- When the active calibration appears or disappears while Tracking is on (layout or camera change), reconcile the
  camera, so it starts or stops.
- Turning Tracking on before camera permission is decided shows the explanation (F2); the pending intent resumes
  tracking once granted, as it did for Live.

**3. Tracking loop (SPEC F16, D28, D29).** Split into a pure internal struct `TrackingLoop` (its own file, fully
unit tested) and an `AppModel+Tracking.swift` extension that feeds it and does the I/O.

*`TrackingLoop` state:* `polled: DisplayID?` (last accepted poll), `override: (display: DisplayID, before:
DisplayID?)?`, `inFlight: DisplayID?`, `epoch: Int`.
- `focusedDisplay` is `inFlight ?? override?.display ?? polled`.
- `isFocusing` is `inFlight != nil`.
- `beginAttempt(_ display:)`: only when `inFlight == nil`. Remembers `before = focusedDisplay` (as it was), sets
  `inFlight = display`, and increments `epoch`.
- `finishAttempt(_ display:, result:)`: clears `inFlight` and increments `epoch`. Then:
  - `.focused` → `polled = display`, `override = nil`;
  - `.noWindow` or `.failed` → `override = (display, before)`;
  - `.notTrusted` → nothing else changes.
- `pollStarted() -> Int` returns the current `epoch`.
- `pollFinished(_ display:, epoch:)` ignores the result if `epoch` changed or an attempt is in flight. Otherwise:
  - with an override, a result equal to `override.before` keeps the override (that focus is already known); any
    other result clears the override and becomes `polled`;
  - without an override, the result becomes `polled`.
- `lookChanged(to classification:, enterMargin:)` clears the override when the classification is `.display` with a
  `best` other than the override's display and `margin >= enterMargin` (the look moved on).
- `reset()` clears everything and increments `epoch`.

*Per live sample* (`AppModel+Tracking`), when tracking is active: Tracking on, no gate test or setup run, an active
calibration, and a decider.
1. Process with `SwitchContext(focusedDisplay: loop.focusedDisplay, isFocusLocked: holdReason != nil &&
   holdReason != .switching, targets: trackedTargets)`. Sway's own request in flight is not a lock (review fix: a
   lock cancels the decider's cooldown, which must run from the switch; the loop already reports the target as
   focused and refuses a second request). `holdReason` is the first that applies of:
   - `.focusLock` (Focus Lock on);
   - `.swayInFront` (Sway is the active app);
   - `.focusTest` (a Focus Test countdown or request is running);
   - `.switching` (`loop.isFocusing`).
2. Keep `previewDecision`, the dwell start, and the latency as the preview did. Then call
   `loop.lookChanged(to: decision.classification, enterMargin:)` with the current settings' enter margin.
3. On `decision.switchTo = D`:
   - Not trusted (`isAccessibilityTrusted` false) → no request; the status shows Needs Accessibility.
   - Else `loop.beginAttempt(D)`, then `focus.focus(display: D, in: layout)` in a `Task`. On completion (ignored if
     tracking stopped or the loop was reset since), `loop.finishAttempt(D, result:)`, add a switch-log entry, and
     log once at info level (category `"tracking"`): outcome, app name, display name, method, ms. **Never titles.**
     `.notTrusted` also sets `isAccessibilityTrusted = false`.
- `trackedTargets`: the first `SwayPolicy.maxTrackedDisplays` displays of the current layout, in layout order, that
  the active calibration profiles. `nil` when that is every display the profile has.
- The decider is `engine.makeDecider(profile: activeCalibration.profile, settings: sensitivity.switchSettings())`,
  rebuilt (and `loop.reset()`) when the active calibration changes, when a tracking stream starts, and when the
  sensitivity changes. `sensitivity` is read from `sway.switchSensitivity` (default `SwitchSensitivity.default`);
  M5 adds the controls.
- Reset the decider and the loop on a layout change, a stream restart, or the camera stopping (as the preview did).

*Focused-display poll* (the `focusedDisplayPollInterval`, 1 s; an injected tick like `focusTick`, so tests call
`trackingTick()`):
- runs only while the camera runs for tracking;
- each tick: refresh `isAccessibilityTrusted = focus.isTrusted()`; then, unless a poll is still running, start one:
  `let epoch = loop.pollStarted()`, `await focus.focusedDisplay(in: layout)`, then `loop.pollFinished(_, epoch:)`;
- also poll at once on `NSWorkspace.didActivateApplicationNotification` (observed through an injected notification
  center, `environment.workspaceNotificationCenter`).

*Sway in front:* `isAppActive`, read from an injected `environment.isAppActive()` at launch and again on
`NSApplication.didBecomeActiveNotification` / `didResignActiveNotification` and `NSWindow.didBecomeKeyNotification` /
`didResignKeyNotification` on `environment.notificationCenter`. Live, it is "active **and** has a key window": after
Sway's last window closes, Sway stays the active app with nothing in front, and switching must not hold then.

**4. Focus Lock (SPEC F17, D27).**
- `focusLocked` (not saved; off at launch) and `toggleFocusLock()`. The Pose Debug "Simulate Focus Lock" toggle
  becomes the real Focus Lock.
- **Shortcut:** `focusLockShortcut: HotKeyShortcut?`, saved under `sway.focusLockShortcut`: an absent key means
  `.focusLockDefault`; the JSON of a shortcut means that shortcut; an empty `Data` means none.
- At launch, register it with `hotKeys.register(_, for: .toggleFocusLock) { [weak self] in self?.toggleFocusLock() }`.
  On `HotKeyError`, keep `shortcutMessage` for Settings, and for the menu banner while the chosen shortcut is not
  registered (a refused change in Settings, with the previous shortcut registered again, is told in Settings only):
  - `.shortcutInUse`: "<shortcut> is already used by another app. Choose another shortcut in Settings.";
  - otherwise: "The Focus Lock shortcut could not be set up."
- `setFocusLockShortcut(_ shortcut: HotKeyShortcut?) -> Bool` for M5: registers the new one first (or unregisters for
  `nil`); on success saves it and clears the message, on failure keeps the previous shortcut registered and
  returns false with the message set.

**5. Status (SPEC F19, D32).** A pure internal `TrackingStatus` enum (its own file) with a pure constructor from a
snapshot struct (camera authorization, camera `CaptureStatus`, `trackingEnabled`, gate or setup running, display
count, whether a calibration fits, Accessibility, Focus Lock, face). The cases, priority, symbols, and lines are
exactly SPEC F19's table. Each case has `symbol` and `line`. `MenuBarLabel` uses them.
- "Camera busy" is chosen when the interruption text says another app is using the camera.
- The status line in the popover appends " · <camera name>" while the camera runs.
- **Test:** every case's symbol resolves with `NSImage(systemSymbolName:accessibilityDescription:)`.

**6. Menu (SPEC F19).** Layout exactly as SPEC F19's list.
- Banners, at most one, in this order: camera permission; first setup (the library is empty); needs calibration
  (Tracking on, 2+ displays, nothing fits); needs Accessibility (Tracking on, calibrated, not trusted; **Grant
  Access…** as in the Focus Test window); `shortcutMessage`.
- In M4, **Set Up…**, **Calibrate…**, and the needs-calibration button open the gate test window. M5 points them at
  the Setup window.
- The "Looking at" line must not redraw at the frame rate: store a small `LookSummary` value (`.off`, `.noFace`,
  `.elsewhere`, `.display(name)`) and assign it only when it changes.
- Keep the popover's height constant when tracking starts or stops (one line per row in every state).

**7. Pose Debug.** The Switch preview section shows the real loop: "Focus: <display or Unknown>" from
`loop.focusedDisplay`, the hold reason ("Focus Lock on", "Sway is in front", "Switching…") when the context is
locked, and the switch log, now of real switches ("Focused <app> on <display> in <ms> ms, held <s> s", "No window on
<display>", "Failed: <reason>"). The section's own focus calls are gone; only the loop calls `focus.focus`.

**8. Gate test.** It holds tracking while it runs (as the preview did) and saves its profile into the library.
`SwayPolicy.maxTrackedDisplays` is now 3: update the gate setup's "Sway v1 will track N displays" note and its
tests so they show only for more than 3 displays.

**9. Tests** (fakes for `HotKeyRegistering` and `LoginItemControlling` in the test target; a fake workspace
notification center):
- `TrackingLoop`, one test per rule above, including stale polls after an attempt, an override kept by a poll
  equal to `before`, cleared by another poll and by a look elsewhere, and `.notTrusted`;
- a held look fires exactly one `focus.focus(display:in:)` for the right display, and the log names app and display
  (never the title);
- no request while: Focus Lock on, Sway active, a Focus Test request running, a request in flight, not trusted;
- a stream restart or layout change resets the loop; a late focus result after a reset is ignored;
- `trackedTargets` with 2, 3, and 4 displays;
- the poll runs only while tracking runs, and an app activation triggers one;
- the library: migration from `sway.calibrationProfile`, saving after a gate fit, resolution after a layout change
  and a camera change, the camera starting or stopping as a calibration appears or disappears;
- launch with `sway.trackingEnabled = true` starts the camera without any window; automatic turn-offs do not
  change the saved value;
- Focus Lock: toggling, the hot key handler toggles, default and saved shortcuts, a registration failure message,
  `setFocusLockShortcut` keeping the old shortcut on failure;
- `TrackingStatus`: every row of the table and the priority between neighbors; every symbol resolves;
- the "Looking at" line changes only when the summary changes.

#### 6.5.3 M5 additions to `SwayUI` (builder-ui-m5, after builder-ui-m4)

No public API change. New window IDs `"setup"` and `"settings"`, launch-guarded like the others.

**1. Setup window (SPEC F20, D30).** `Window("Set Up Sway", id: "setup")`. A pure internal `SetupFlow` state machine
(its own file, unit tested) decides the step from the facts; `AppModel+Setup.swift` drives it.
- Steps: `.cameraAccess`, `.accessibility`, `.cameraCheck`, `.calibrating`, `.result`.
  - Opening the window starts at the first step that applies: camera access unless authorized; Accessibility unless
    trusted (or skipped this session); otherwise camera check. So a recalibration opens at the camera check.
  - **Camera access:** the F2 explanation and button. When access is granted, move on.
  - **Accessibility:** the F12 text, **Grant Access…** (`grantAccessibility()`), and **Skip for now**. Poll trust
    once a second while this step shows; move on when granted.
  - **Camera check:** the camera runs (`wantsCamera` includes "the Setup window is on the camera check or calibrating
    step"). Show the camera picker, the advice text from SPEC F20, and a live hint from a pure `FramingAdvice`
    function of the latest pose: no face → "Sway can't see your face yet."; `faceBounds.height < 0.18` → "Move a
    little closer to the camera."; `> 0.6` → "Move back a little."; face center outside 0.2…0.8 on either axis →
    "Center your face in the camera's view."; otherwise "Looks good." Refresh the hint at most five times a second.
    **Start calibration** is enabled with 2 or more displays ("Connect a second display to calibrate." otherwise).
  - **Calibrating:** the gate machinery with a purpose of `.calibration`: 2 rounds, 2.5 s hold, 1.5 s settle,
    `includeLandmarks` false, the same overlays, Esc and Cancel (back to the camera check, with "Calibration
    cancelled."). Show "Look at the dot on <display>" and the step count. A layout change or losing the camera
    cancels it, as for the gate test.
  - **Result:** fit with `engine.fitProfile(from:features: .visionAngles, rounds: nil)`.
    - When the fitted profile lacks any display of the traced layout (the fitter drops a display with too few face
      samples), save nothing and say "Sway couldn't see your face well enough while you looked at <A>. Make sure the
      camera sees you from every display, then calibrate again." (review fix: such a calibration can never cover the
      connected displays).
    - On success, save it into the library, analyze the trace with `analyzer.analyze(_, thresholds: .default)`, and
      show the Vision-angles verdict: `go` → "Calibration looks good."; `marginal` → "Calibration saved. <A> and
      <B> are close together, so switching between them may be slower." (the weakest pair); `noGo` →
      "Calibration saved, but <A> and <B> are hard to tell apart. Try moving the camera, then calibrate again.";
      `insufficientData` → "Calibration saved, but Sway saw your face only briefly on some displays. If switching
      feels unreliable, calibrate again." (Fair).
    - On a fit failure, save nothing and show the F10 message.
    - **Start tracking** sets Tracking on (a user action, so it is saved) and closes the window. **Calibrate again**
      returns to the camera check.
  - In DEBUG, save the calibration trace like a gate trace. It never replaces the gate window's report.
- Closing the window mid-calibration cancels it. Tracking holds while the window is on the camera check or
  calibrating step. The result step does not hold (review fix): in front, "Sway in front" holds anyway; left behind
  other apps, it must not stop switching unseen.

**2. Settings window (SPEC F21, D31, D33).** `Window("Sway Settings", id: "settings")`.
- **General:** "Open Sway at login" toggle. It reads `loginItem.status` when the window appears and after each
  change: on for `.enabled` and `.requiresApproval`. `.requiresApproval` adds "Allow Sway in System Settings >
  General > Login Items." with **Open Login Items** (`loginItem.openSystemSettings()`); `.unavailable(text)` disables
  the toggle and shows the text; a `LoginItemError` shows its message under the toggle.
- **Switching:** "Hold time" slider over `SwitchSensitivity.dwellRange` in 0.05 s steps with its value ("0.40 s");
  "Switch confidence" as a 5-step slider labelled Relaxed … Strict; **Restore Defaults**. Each change saves
  `sway.switchSensitivity` and rebuilds the decider at once.
- **Focus Lock shortcut:** shows the shortcut ("⌃⌥⌘L", or "None"). **Record Shortcut** → "Type a shortcut…": a local
  key-down monitor (`NSEvent.addLocalMonitorForEvents`) in this window only, removed when recording ends. Esc
  cancels. A pure helper maps the event's key code, modifier flags, and `charactersIgnoringModifiers` (uppercased;
  names for Space, Return, Tab, Delete, Escape, arrows, and F1–F20) to a `HotKeyShortcut`. An invalid shortcut shows
  "Use Control, Option, or Command with a key." While recording, the current shortcut is unregistered; it is
  registered again if recording is cancelled. A new one goes through `setFocusLockShortcut`, and its failure message
  shows here. **Reset to ⌃⌥⌘L** and **Clear**.
- **Camera:** the camera picker.
- **Calibrations:** one row per saved profile, newest first: its displays by name (from the current layout or
  saved analysis names, else "Unknown display"), the camera, and the date. The active one (by key) says "In use".
  **Delete** removes it at once (calibrating again restores it). **Calibrate…** opens the Setup window.

**3. Prompts (SPEC F22, F23).** The menu's **Set Up…**, **Calibrate…**, and needs-calibration buttons open the Setup
window. The needs-calibration banner says "New display setup. Calibrate so Sway can switch between them." with
**Calibrate (about 20 s)…**; when the library has a calibration for these displays with another camera, it says
"No calibration for <camera> yet." instead. The menu gets **Settings…** (SF Symbol `gearshape`) after Calibrate….

**4. Tests:**
- `SetupFlow`: each starting step from the facts, skipping, moving on when a permission is granted, cancel and
  Calibrate again, and a fit failure;
- `FramingAdvice`: every hint and its boundaries;
- a full calibration on the injected clock: the overlays, 2 rounds × displays, no landmarks, a saved library entry,
  the verdict texts, Start tracking saving `sway.trackingEnabled`;
- the camera runs for the camera check and calibrating steps, and stops when the window closes (with Tracking off);
- sensitivity: the slider values, saving, the decider rebuilt with the mapped settings, Restore Defaults;
- the shortcut mapping helper (letters, digits, named keys, F-keys, invalid combinations), recording success,
  cancel (the old shortcut registered again), a registration failure keeping the old one, Clear, Reset;
- login item states and errors against a fake;
- the calibration list: rows, "In use", Delete updating the library and the active calibration;
- the banners' texts and the buttons opening the Setup window.

#### 6.5.4 M6 additions to `SwayUI` (builder-ui-m6): the design pass

No public API change. New `UserDefaults` keys: `sway.accentChoice` (String: `"sway"` or `"system"`, absent =
`"sway"`), `sway.edgeGlowEnabled` (Bool, absent = true), `sway.focusLockNoticeEnabled` (Bool, absent = true).
Behavior (switching, holds, camera rules, calibration) does not change.

**1. Theme and accent (SPEC F24, D34, D35).**
- `SwayPalette` keeps the brand values (forest `0x2F5D3A`, sage `0x9CAF88`, ivory `0xF6F3EA`, charcoal `0x2B2B2B`) and
  gains `green`: a dynamic color (`NSColor(name:dynamicProvider:)`), forest in light appearances and `0x6FAF84` in dark
  ones. `green` is Sway green everywhere (tint, glow, the mark in the popover).
- `AccentChoice` enum (`.sway`, `.system`), stored as above; `AppModel.accentChoice` with `setAccentChoice(_:)`.
  `tint: Color?` is `SwayPalette.green` for `.sway` and `nil` for `.system`.
- Every window's root view and the menu popover apply `.tint(model.accentChoice.tint)`: menu, Pose Debug, gate test,
  Focus Test, Setup, Settings. Text and glyphs that used `SwayPalette.accent(for:)` keep it.
- The app has **no** asset-catalog accent color (orchestrator): with one, macOS's Multicolor setting would show it
  through, so "Match macOS" would still look green. Without it, Match macOS is exactly the system accent.

**2. The Swing mark and the menu bar icon (SPEC F25, D36, D37).**
- `SwayMarkGeometry`: the mark in a 100 × 100 unit square: an arc `M 24 40 Q 50 86 76 40` (quadratic), a start point
  at (24, 40) and an end point at (76, 40), y down. One definition shared by the drawing below and a SwiftUI
  `SwayMark` view (stroke arc with round caps, small start dot, larger end dot; colors as parameters) for the popover
  header and the welcome step.
- `MenuBarGlyph` enum: `.tracking`, `.paused`, `.focusLock`, `.attention`, with a pure mapping from `TrackingStatus`
  exactly as SPEC F25's table. Each glyph has a pure `MenuBarGlyph.Style` (`opacity`, `hollowEnd`, `lockBadge`,
  `alertDot`): tracking = (1, false, false, false); paused = (0.5, true, false, false); focusLock = (1, false, true,
  false); attention = (1, false, false, true).
- `MenuBarIcon.image(for: MenuBarGlyph) -> NSImage`: 18 × 18 pt, `isTemplate = true`, drawn with `NSBezierPath` from
  `SwayMarkGeometry` scaled to the image (arc width about 1.8 pt, start dot radius about 1.4 pt, end dot about 2 pt;
  hollow = a 1 pt ring), plus the lock badge at the bottom right or the dot at the top right (cut out from the mark
  with a clear ring so it reads at 18 pt). Drawn once per glyph and cached (`static let`).
- `MenuBarLabel` shows `Image(nsImage: MenuBarIcon.image(for: model.menuBarGlyph))` and keeps its accessibility label
  and value. `menuBarGlyph` derives from `trackingStatus`, which already changes only on status changes.
- `TrackingStatus.symbol` stays for the popover's status line glyph.

**3. Welcome and Setup restyle (SPEC F26, D40).**
- `SetupFlow` gains a first step `.welcome`, used only when Setup opens with an empty calibration library. **Get
  Started** moves to the first step that applies after it. The welcome step is not counted in "Step N of 5".
- The welcome step's text is exactly SPEC F26's. Layout: the `SwayMark` (64 pt, green arc on an ivory/charcoal
  rounded square matching the appearance), the title, the line, the privacy text with an SF Symbol `lock.shield`, the
  button (prominent, tinted).
- All Setup steps share one header view (the mark at 24 pt and the step title) and the same padding and width.

**4. Edge glow and Focus Lock notice (SPEC F27, F28, D38, D39).**
- A new internal protocol `FeedbackPresenting` (`@MainActor`), injected as `environment.feedback`:
  `func showGlow(on display: DisplayInfo, animated: Bool)` and
  `func showNotice(_ text: String, symbol: String, on display: DisplayInfo, animated: Bool)`.
  Tests use a fake that records calls. The live `FeedbackOverlayController` reuses `OverlayPanel` (click-through,
  non-activating, never key or main, `.screenSaver` level, every Space, over full-screen apps).
  - **Glow:** one reusable panel, moved to the display's frame. A 4 pt `SwayPalette.green` border with a soft outer
    glow (about 10 pt, 40% opacity) along the screen edges (rounded corners on displays that have them are not
    required). Animated: fade in 0.1 s, hold 0.05 s, fade out 0.2 s. Not animated: shown for 0.35 s, then hidden. A
    new glow while one shows restarts it on the new display. Hidden (`orderOut`) between glows.
  - **Notice:** one reusable panel sized to a pill (`NSVisualEffectView`, `.hudWindow` material, rounded, the SF
    Symbol and text), centered horizontally, 48 pt below the top of the display's visible frame. Animated: fade in
    0.15 s, hold 1 s, fade out 0.3 s; not animated: shown for 1.3 s.
  - The panels are created lazily on first use and kept; nothing runs while hidden.
- **When:** the glow follows a tracking switch whose result is `.focused`, when `sway.edgeGlowEnabled`. Never for
  Focus Test requests or failed and no-window results. The notice follows a Focus Lock toggle **from the hot key**
  only (a separate entry point from the menu switch), when `sway.focusLockNoticeEnabled`; it shows on
  `loop.focusedDisplay`, else the display with the menu bar (the layout's main display).
- `animated` is `!environment.reduceMotion()`; live: `!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

**5. Motion (SPEC F29, D41).** SwiftUI: Setup step changes and the menu banner use `.animation(.easeInOut(duration:
0.2), value:)` with `.transition(.opacity)`, and no animation when `@Environment(\.accessibilityReduceMotion)` is
true. No other new animations. Nothing animates at the frame rate.

**6. Settings → Appearance (SPEC F24, F27, F28).** A new first section "Appearance":
- "Accent color" as a segmented picker: **Sway green** / **Match macOS**;
- "Glow on the display that gets focus" toggle;
- "Show a notice when the shortcut toggles Focus Lock" toggle.
Each change saves at once and applies at once.

**7. Popover header.** The `SwayMark` (16 pt, Sway green regardless of the accent) before "Sway".

**8. Tests:**
- `MenuBarGlyph` mapping for every `TrackingStatus` case, and each glyph's style;
- `MenuBarIcon` images are 18 × 18 pt templates, one per glyph, the same instance on repeated calls;
- accent: default, persistence, `tint` per choice;
- the welcome step: shown only with an empty library, Get Started moves on to the right step, not counted in the
  step number;
- glow: one `showGlow` per `.focused` tracking switch with the target display; none when disabled, for `.noWindow`,
  `.failed`, `.notTrusted`, or Focus Test requests; `animated` follows `reduceMotion`;
- notice: the hot key toggle shows "Focus Lock on" then "Focus Lock off" with `lock.fill` / `lock.open`, on the
  focused display or the main one; none from the menu switch; none when disabled;
- the Appearance settings save and apply;
- view smoke tests for the welcome step, the Appearance section, and the popover header;
- no frame-rate observation changes (the existing observation-count tests still pass).

#### 6.5.5 M7 additions to `SwayUI` (builder-ui-m7): hardening

No public API change. Behavior with a face present and nothing changing does not change. `SwayModels` already has
`SuspendReason.sessionInactive`, `PoseDemand`, and `PoseSource.setDemand(_:)` (a default no-op).

1. **Display and Space holds (SPEC D44).** Two new `TrackingHold` cases, ordered after `focusTest` and before
   `switching`: `displaysChanging` and `spaceChanging`.
   - `displaysChanging` starts on `NSApplication.didChangeScreenParametersNotification` (observed on
     `environment.notificationCenter`) and ends when `layoutDidChange` has applied the new layout, or after 0.75 s,
     whichever is first. Starting it resets the loop (as a layout change does) and cancels an in-flight switch.
   - `spaceChanging` starts on `NSWorkspace.activeSpaceDidChangeNotification` (observed on
     `environment.workspaceNotificationCenter`), lasts 0.6 s, and ends with one poll of the focused display.
   - Both are invisible in the menu. Timers follow how the existing delayed work is injected, so no test sleeps.
   - **Cap and log (review fix).** Notifications that do not change the layout still restart the 0.75 s timer, so a
     display that posts every 0.5 s would stop switching for good. A display hold never lasts more than 3 s from its
     first notification: later notifications still reset the loop but do not extend the timer past that. Log each hold
     at info level when it starts and when it ends: which hold, how long it lasted, and whether a layout, the timeout,
     or the cap ended it (never window titles).
     After a cap end, notifications that keep arriving less than 0.75 s apart are ignored (no hold, no reset); a pause
     of 0.75 s or more lets the next notification hold again. (Otherwise a display posting every 0.5 s would start a
     new hold right after each cap and switching would still stop.)
2. **Pose demand (SPEC D45).** `AppModel` calls `poseSource.setDemand(_:)` whenever the wanted demand changes
   (deduplicated) and once after each start. `.full` whenever the camera runs for anything but plain tracking
   (Setup's camera check or calibration, the gate test, a calibration running, Pose Debug open, a Focus Test).
   `.reduced` while `trackingHold == .focusLock` or the status is `needsAccessibility`. `.adaptive` otherwise while
   tracking. The fake pose source records demands.
3. **Suspend reason text.** `.sessionInactive` reads "another user's session" (done in `SwayModels`/`SwayUI`
   `CaptureStatusPresentation`; add a test).
4. **Only a running camera switches.** `processTracking` also requires the capture status to be running.
5. **Fewer environment refreshes.** Coalesce camera connect/disconnect notifications into one `refreshEnvironment`
   0.5 s after the last one, and skip it while the capture status is `.suspended`; run it once when the status leaves
   `.suspended`.
6. **Camera grace after display changes (SPEC §6).** When the camera should stop only because the displays changed (no
   calibration fits, fewer than 2 displays), stop it 2 s later instead of at once, and cancel the stop if the layout
   recovers meanwhile. Stopping for any other reason (Tracking off, Pause, quit, lock) stays immediate.
7. **USB camera fallback (SPEC D46).** When the camera the user chose is not connected and capture is interrupted
   for 5 s, restart the pose source with a connected camera that has a calibration for the current displays (prefer
   the built-in). When the chosen camera is connected again, restart with it. Never switch cameras while a
   calibration, the gate test, or Setup runs. The saved camera choice is never changed by a fallback.
   - **No usable fallback (SPEC D46, revised 2026-10-26): turn Tracking off.** When the 5 s pass and no connected
     camera has a calibration for the current displays, set `trackingEnabled = false` in memory only (the saved choice
     is untouched, as for a camera failure, D23) and stop the camera. While that camera is still not connected, the
     status reads "<camera name> disconnected" instead of "Paused". Tracking does not come back by itself when the
     camera returns: the status returns to "Paused" and the user turns Tracking on. The same applies if a stand-in
     camera is later disconnected too and nothing else is usable. A fallback that does start (a calibrated camera
     exists) is unchanged.
   - **A failed restart during a fallback never turns Tracking off (review fix).** When the restart that a fallback
     started (to the stand-in, or back to the chosen camera) fails with `.deviceUnavailable` or `.noDevice`, keep
     Tracking on: a camera that was just plugged in may not be ready to open. If switching back failed, put the
     stand-in back and reconcile; if the stand-in itself failed, try again at the next device change. Other errors keep
     today's behavior.
8. **Steadier "No face".** The `noFace` status shows after 0.5 s without a face; a face shows at once.
9. **Tests**, all against fakes: each hold (start, end by layout, end by timeout, in-flight switch dropped, no switch
   while held, polls after); the demand for every mode; the status text; the running-only rule; the coalesced
   refresh and the suspended skip; the camera grace and its cancel; the fallback (5 s, calibrated fallback only, switch
   back, never during calibration, saved choice unchanged); the `noFace` debounce; the observation-count tests still
   pass.

#### 6.5.6 0.1.x tuning: switching timing (builder-timing)

SPEC D49, F35. Owners for this task: `SwayModels/SwitchSensitivity.swift` and its tests, `SwayUI` and its tests, and
one new test file in `SwitchEngineTests`.

1. **`SwitchSensitivity` gains `cooldown`** (seconds, the decider's "no new dwell starts after a switch"):
   - `static let cooldownRange: ClosedRange<Double> = 0.2...1.5`; `dwellRange` becomes `0.05...1.5`.
   - `default` is `SwitchSensitivity(dwell: 0.40, cooldown: 0.75, confidenceLevel: 2)` and still equals
     `SwitchSettings.default` when turned into settings.
   - `public init(dwell:cooldown:confidenceLevel:)` clamps all three. Keep the old `init(dwell:confidenceLevel:)`
     (cooldown 0.75) so existing callers compile.
   - **Saved values keep working:** `Codable` is hand-written; a saved `{"dwell":0.2,"confidenceLevel":2}` with no
     `cooldown` decodes with 0.75. Encoding always writes all three. Unknown or out-of-range values clamp.
   - `switchSettings(base:)` also sets `settings.cooldown`.
   - `static let instant`: hold time 0.10 s and cooldown 0.30 s. A method `applyingInstantTiming()` returns the
     sensitivity with those two values and the same `confidenceLevel`.
2. **`SwayUI`:**
   - `AppModel.setCooldown(_:)` (snapped to 0.05 s and clamped, saved to `sway.switchSensitivity`, rebuilds the decider
     and resets the loop at once, exactly like `setHoldTime`) and `AppModel.useInstantTiming()`.
     `restoreSensitivityDefaults()` restores all three values.
   - `SensitivityPresentation`: the cooldown's step (0.05) and snapping helper, and the text ("0.75 s", the same
     format as the hold time).
   - Settings → Switching: after "Hold time", a **"Pause after a switch"** slider over `cooldownRange` with its value
     and the caption from SPEC F35; a **"Use Instant timing"** button after the confidence slider; Restore Defaults
     stays, disabled at the defaults. The hold time slider uses the new range.
   - One info log line in the `tracking` category whenever the sensitivity is set or loaded at launch: "Switching
     settings: hold 0.10 s, pause 0.30 s, confidence Easy" (never anything else).
3. **Tests:**
   - `SwayModelsTests`: clamping of every field; the default equals `SwitchSettings.default`; decoding old saved JSON
     without `cooldown`; round trip; `switchSettings()` carries the cooldown; the instant preset keeps the confidence.
   - `SwitchEngineTests` (new file): with default settings a switch to B followed at once by a held look back at A
     fires the second switch about 1.0 s after the first (cooldown 0.75 + dwell 0.4 rounded to frames); with the
     instant preset about 0.4 s after; and a head sweep through a middle display faster than the hold time still
     does not switch there with the instant preset at 15 fps. Use the existing scenario helpers.
   - `SwayUITests`: the setters (snapping, clamping, saving, applying to the decider, resetting the loop), the preset
     button, Restore Defaults, the presentation text, the Settings view renders with the new controls, the log line
     wording, and an old saved value loading with the default cooldown. The observation-count tests still pass.

### 6.6 `SwitchEngine` (builder-engine, M2)

**Public API (exact):**
```swift
public struct PoseSwitchEngine: SwitchEngineMaking { public init() }
```
Everything else is `internal`. Split into one primary type per file: the profile fitter, the classifier, the
state machine (for example `SwitchStateMachine: SwitchDeciding`), and the engine facade.

**Fitting: `fitProfile(from:features:rounds:)`**
1. Use segments with a non-nil `displayID`, and, when `rounds` is non-nil, only those whose `round` is in it.
2. Feature points per display. A sample counts when its pose is non-nil and the features are present:
   - `.visionAngles` → (`yaw`, `pitch`);
   - `.landmarkAngles` → (`landmarkYaw`, `landmarkPitch`), both non-nil.
3. If the used segments have face samples but none has the features, throw
   `CalibrationError.featuresMissing(features)`. If they have no face samples at all, or no segment is used, throw
   `CalibrationError.tooFewDisplays`. Every face has Vision angles, so `featuresMissing` only happens for landmarks.
4. Keep displays with at least `GateThresholds.default.minFaceSamplesPerDisplay` (30) points. If fewer than 2 remain, throw
   `CalibrationError.tooFewDisplays`.
5. Per kept display: the mean, and the sample standard deviation (n − 1) of each axis.
6. Order the displays by the trace layout's order, followed by any display not in the layout, in order of first
   appearance.
7. Scales:
   - `yawScale = max(1.5, sqrt(mean over kept displays of yawStd²)))`;
   - `pitchScale = max(2.5, yawScale, sqrt(mean of pitchStd²))`.
8. The remaining fields:
   - `layoutFingerprint = trace.layout?.fingerprint ?? ""`;
   - `cameraName = trace.cameraName`;
   - `createdAt = trace.createdAt`, so fits are deterministic;
   - `features` as given.

**Classification: `classify(_:with:settings:)`**
1. `.noFace` when:
   - `pose` is `nil`;
   - `faceConfidence < settings.minFaceConfidence`;
   - or the profile's features are missing from the pose.
2. Let (x, y) be the pose's features. For each display profile:
   `d = sqrt(((x − yaw) / yawScale)² + ((y − pitch) / pitchScale)²)`.
3. `best` is the smallest d (ties go to the earlier display in profile order), and `runnerUp` is the second.
   `margin = (dRunnerUp − dBest) / (dRunnerUp + dBest)`, or 0 when the sum is 0.
4. The pose is `.elsewhere` when:
   - `x < minYaw − elsewhereYawMargin` or `x > maxYaw + elsewhereYawMargin`;
   - or `y < minPitch − elsewherePitchMargin` or `y > maxPitch + elsewherePitchMargin`.

   The min and max are taken over the profile's display means. An elsewhere result keeps `best`, `runnerUp`, and
   `distances` but has `margin = 0`.
5. Otherwise the result is `.display`. `distances` always holds every display's d.

**State machine: `makeDecider(profile:settings:)`** returns a fresh, idle `SwitchDeciding`.
- **State:** `idle`, `dwelling(display, start, lastSupport)`, or `coolingDown(until)`, plus the last timestamp.
- **Shorthand:**
  - `t` is `sample.timestamp`;
  - `c` is `classify(sample.pose, …)`;
  - `inTargets(D)` is `context.targets == nil || context.targets!.contains(D)`;
  - `eligible(c, m)` is `c.kind == .display && c.margin >= m && inTargets(c.best!)`;
  - `ε = 1e-6` s. Every time comparison allows it in the direction that meets the threshold. Timestamps are large
    (about 3·10⁵ s of host uptime), so `t − start` for an exact 0.4 s can compute as 0.39999999996 and
    would otherwise fire one frame late:
    - a dwell is complete when `t − start >= dwell − ε`;
    - a cooldown is over when `t >= until − ε`;
    - a gap is exceeded when `t − lastSupport > maxGap + ε`.

`process(sample, context)` runs these steps:
0. If `t` is less than the last timestamp, `reset()` first (a new stream). Then record `t`.
1. Compute `c`.
2. **Focus lock.** If `context.isFocusLocked`: set the state to `idle` and return
   `(switchTo: nil, phase: .locked, reason: .focusLocked)`.
3. **Cooldown.** If cooling down and the cooldown is not over: return `(nil, .coolingDown(until), .coolingDown)`.
   Otherwise set the state to `idle` and continue.
4. **Dwelling on D:**
   - (a) If `D == context.focusedDisplay`: set `idle` and continue at step 5.
   - (a2) If the gap is exceeded (`t − lastSupport > maxGap + ε`, for example after a camera stall): set `idle`
     and continue at step 5, which may start a fresh dwell on this sample.
   - (b) If `c.kind == .display && c.best == D && c.margin >= stayMargin && inTargets(D)`, then
     `lastSupport = t`:
     - if the dwell is complete (`t − start >= dwell − ε`): set the state to `coolingDown(t + cooldown)` and return
       `(switchTo: D, phase: .coolingDown(t + cooldown), reason: nil)`;
     - otherwise return `(nil, .dwelling(D, progress: min(1, (t − start) / dwell)), .dwelling)`.
   - (c) Else, if `eligible(c, enterMargin)` with a best E ≠ D: set `idle` and continue at step 5, which may
     start a dwell on E.
   - (d) Removed: (a2) now handles an exceeded gap.
   - (e) Otherwise return `(nil, .dwelling(D, progress), .dwelling)`. The dwell clock keeps running through
     short gaps, but a switch fires only on a supporting sample.
5. **Idle**, checked in this order:
   - `.noFace` → `(nil, .idle, .noFace)`;
   - `.elsewhere` → `.elsewhere`;
   - best not in targets → `.notATarget`;
   - best == focused → `.alreadyFocused`;
   - `margin < enterMargin` → `.uncertain`;
   - otherwise start `dwelling(best, start: t, lastSupport: t)` and return
     `(nil, .dwelling(best, 0), .dwelling)`.

     If `dwell <= 0`, fire immediately instead, as in 4(b).
- **`holdReason(c)`** uses the same mapping as step 5, without starting a dwell. If no reason applies (for example
  `stayMargin > enterMargin`), it returns `.uncertain`.
- **`reset()`** returns to `idle` and forgets the last timestamp.

**Logging** uses category `"engine"`, at debug level only, and never per sample at info level.

**Tests** (Swift Testing; no sleeps; seeded RNG in the test target, such as a small SplitMix64 copy):
- **Fitting:**
  - means and stds;
  - scale floors, and `pitchScale >= yawScale`;
  - a display under 30 points is dropped;
  - unlabeled segments are ignored;
  - the `rounds` filter;
  - `featuresMissing` and `tooFewDisplays`;
  - layout order;
  - deterministic output.
- **Classification:**
  - nearest wins, with a hand-computed margin;
  - the same angular offset counts less in pitch than in yaw when `pitchScale > yawScale`;
  - each side of the elsewhere box;
  - no pose, low confidence, and missing landmarks give `.noFace`.
- **State machine**, one test per rule:
  - fires at exactly the first sample with `t − start >= dwell − ε`, including timestamps near 3·10⁵ s where
    the exact difference rounds below `dwell`;
  - a glance shorter than the dwell never fires;
  - a gap ≤ `maxGap` survives, and a longer one cancels. Test both a run of non-supporting samples and a hole
    in the stream (no samples for 3 s, then a supporting sample, which starts a fresh dwell and does not fire);
  - looking back at the focused display cancels;
  - hysteresis: a margin between stay and enter keeps a dwell going but cannot start one;
  - cooldown blocks;
  - focus lock blocks and cancels;
  - `targets` are respected;
  - already focused gives `.alreadyFocused`;
  - a nil focused display allows any switch;
  - a backwards timestamp resets;
  - `dwell = 0` fires immediately.
- **Synthetic scenarios**, at 15 fps, with three displays at yaw 61 / 42 / 2 and pitch 5 / 10 / 8, std 1.5 / 2.5,
  fitted from a synthetic labeled trace:
  1. 120 s at one display with Gaussian noise of twice the std, plus random single-frame face drops (2%):
     0 switches.
  2. 60 s at the midpoint between two adjacent displays, with noise of half the std: 0 switches. (Wider noise
     legitimately crosses the enter margin now and then; do not tune the defaults to make a test pass.)
  3. 20 glances of 0.25 s to another display: 0 switches.
  4. 20 intentional looks, each a 0.3 s linear turn and a 2 s hold, alternating between displays: exactly 20
     switches. Each fires within `dwell + 1/15 s` of the first sample with margin ≥ enter on the target.
  5. A 0.25 s transit from the leftmost to the rightmost display, crossing the middle one: exactly 1 switch, to
     the rightmost.
  6. A 2 s look 40° down in pitch (keyboard): 0 switches, with the reason `.elsewhere`.
- **Recorded trace:**
  - Load `Fixtures/gate-trace-2026-10-24.json` from `Bundle.module` and decode a `PoseTrace` with `JSONDecoder`
    (`.iso8601` dates). It has 3 displays × 2 rounds × 75 samples, with segments 1.6 s apart.
  - Fit on round 1 with `.visionAngles` and replay round 2's segments in order. Start with
    `focusedDisplay = first segment's display`, and set it to each switch's target (perfect focus). Expect
    exactly 2 switches, to the 2nd and 3rd segments' displays, each within `dwell + 1/15 s` of that segment's
    first sample, and no others.
  - Run the same in reverse: fit on round 2, replay round 1.
  - At least 99% of round-2 samples classify as `.display` with their segment's display as `best`.

### 6.7 `FocusControl` (builder-focus, M3)

**Public API (exact):**
```swift
public final class AXFocusController: FocusControlling { public init() }
```
Everything else is `internal`.

**Window list.**
- Read `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`. It is
  ordered front to back.
- Parse each entry into an internal `WindowRecord` with these fields:
  - `number` (`kCGWindowNumber`);
  - `processID` (`kCGWindowOwnerPID`);
  - `ownerName` (`kCGWindowOwnerName`, or "" if absent);
  - `layer` (`kCGWindowLayer`);
  - `bounds` (`CGRect(dictionaryRepresentation:)` of `kCGWindowBounds`);
  - `alpha` (`kCGWindowAlpha`, default 1).

  Entries without a number, pid, or bounds are skipped. The parser is a pure function over
  `[[String: Any]]`, so it can be tested with fixtures.
- **Normal window filter** (pure). A window counts only if all of these hold:
  - `layer == 0`;
  - `alpha > 0.01`;
  - `width >= 120` and `height >= 80`;
  - `processID != own pid`;
  - `ownerName` is not one of "Window Server", "Dock", "WindowManager".

**Coordinates** (pure).
- `DisplayInfo.frame` uses AppKit coordinates (bottom-left origin). Convert to Quartz with
  `CGRect(x: f.minX, y: H − f.maxY, width: f.width, height: f.height)`.
- `H` is the height of the display whose AppKit frame origin is (0, 0). If none has that origin, use the
  `isMain` display's height. An empty layout means no displays.
- **Display assignment:** the display whose Quartz frame has the largest intersection area with the window's
  bounds. On a tie, use the display containing the window's center. No intersection means the window is
  skipped.

**`lastUsedWindows(in:)`**
- For each display, the first (frontmost) normal window assigned to it.
- Titles come from Accessibility only when trusted: the AX title of the matching AX window (see the frame
  matching below), with the messaging timeout 0.25 s, best effort. Otherwise `title = nil`.

**`focusedDisplay(in:)`**
- The frontmost app's pid comes from `NSWorkspace.shared.frontmostApplication`, read on the main actor.
- If that app is Sway, return `nil`.
- If trusted: read the app's `kAXFocusedWindowAttribute`, then `kAXPositionAttribute` and `kAXSizeAttribute`.
  These are Quartz coordinates. Return the display assigned to that frame.
- Otherwise, or when Accessibility cannot read the focused window or its frame: the display of that pid's
  frontmost normal window in the window list. These read-only lookups use a 0.25 s messaging timeout.

**`focus(display:in:)`**, the fallback list (issue #15):
1. Not trusted → `.notTrusted`.
2. The target is the last-used window on `display`. None → `.noWindow(display)`.
3. Prepare the app and window:
   - `app = AXUIElementCreateApplication(pid)`, with `AXUIElementSetMessagingTimeout(app, 0.5)`.
   - Read `kAXWindowsAttribute` and pick the AX window whose position and size match the target's bounds within
     2 pt. This frame matching is a pure function over plain frames.
   - If none matches and the app has exactly one window, use that one.
   - Otherwise return `.failed(target, reason: "Window not found through Accessibility")`.
4. `appActivation` (SPEC D42):
   - `AXUIElementPerformAction(window, kAXRaiseAction)`;
   - set `kAXMainAttribute = true` on the window;
   - `NSRunningApplication(processIdentifier:)?.activate(options: [])`: no options, so only the app's main and key
     windows (the raised one) come forward, not every window of the app.

   Then verify by polling every 25 ms, for up to 300 ms, until both hold:
   - the frontmost pid equals the target's pid;
   - the app's `kAXFocusedWindowAttribute` is `CFEqual` to the window. If it cannot be read, accept the pid match
     alone.

   On success → `.focused(target, method: .appActivation, milliseconds:)`.
5. `accessibilityFrontmost`, the fallback for an app that ignores activation:
   - set `kAXFrontmostAttribute = true` on the app (this can bring all of its windows forward);
   - the raise again;
   - the same verification.

   On success → `.focused(..., .accessibilityFrontmost, ...)`.
6. Otherwise → `.failed(target, reason: "Focus did not move to <app>")`.
7. If the calling task is cancelled between methods → `.failed(target, reason: "Cancelled")`. No further method
   is tried, which lets a Focus Test countdown be cancelled.
- `milliseconds` runs from step 2 to verification. The returned `WindowSummary` includes the AX title when it is
  known.
- **Rules:**
  - No main-thread AX calls: all window-list and AX work runs on one private serial `DispatchQueue`, bridged with
    `withCheckedContinuation`. Main-actor reads (`NSWorkspace` / `NSRunningApplication`) use
    `await MainActor.run`.
  - Never move the cursor, synthesize events, or use private APIs (CI guard, §11).
- **Concurrency:** `AXFocusController` is `Sendable` (a final class with only immutable stored properties).
  `AXUIElement` may cross threads only inside one internal `@unchecked Sendable` wrapper, commented "immutable CF
  reference; these AX calls are thread-safe".
- **Logging:** category `"focus"`. Log the outcome, app name, method, and ms. **Never log window titles.**
- **Tests** (pure parts plus safe smoke tests):
  - record parsing, including missing keys and the alpha default;
  - the normal-window filter;
  - AppKit → Quartz conversion, with the main display at the origin and displays left, right, above (negative
    Quartz y), and below;
  - display assignment: largest overlap, ties to the center, no overlap skipped;
  - last-used selection over a z-ordered list: frontmost per display, own pid excluded, empty displays absent;
  - AX frame matching within 2 pt;
  - `isTrusted()` and `lastUsedWindows(in: .empty)` return without crashing.

  **Never call `requestTrust()` or `focus(display:in:)` in tests.** The test runner may itself have Accessibility
  permission, and a focus call would really move focus.

**Docs (issue #18):** `docs/focus-fallbacks.md` is orchestrator-owned and written from the builder's report:
the fallback list, known limits, and a table for the user's Focus Test results.

### 6.8 `SystemIntegration` (builder-system, M4)

**Public API (exact):**
```swift
@MainActor public final class CarbonHotKeyCenter: HotKeyRegistering { public init() }
@MainActor public final class MainAppLoginItem: LoginItemControlling { public init() }
```
Everything else is `internal`. One primary type per file.

**`CarbonHotKeyCenter`** (Carbon `RegisterEventHotKey`; SPEC §6: no event tap, no monitor, no permission):
- Install one event handler on `GetApplicationEventTarget()` for `kEventClassKeyboard` / `kEventHotKeyPressed`,
  lazily on the first successful registration, and remove it when the last shortcut is unregistered and in `deinit`.
  The C callback reads the `EventHotKeyID` (`GetEventParameter`, `kEventParamDirectObject`, `typeEventHotKeyID`)
  and calls the matching action's handler. Carbon delivers these events on the main thread: use
  `MainActor.assumeIsolated`, never `DispatchQueue.main.sync`.
- Pass context to the callback without global mutable state: an `Unmanaged` reference to an internal box as
  `userData`, or a `static let` lock-protected registry.
- `register(_:for:handler:)`:
  1. `!shortcut.isValid` → throw `.invalidShortcut` without touching Carbon.
  2. Unregister the action's current shortcut, if any.
  3. `RegisterEventHotKey(UInt32(keyCode), carbonModifiers, EventHotKeyID(signature: "SWAY", id: actionID),
     GetApplicationEventTarget(), 0, &ref)`.
  4. `eventHotKeyExistsErr` → `.shortcutInUse`; any other status but `noErr` → `.registrationFailed(status)`. On
     failure the action has no shortcut.
- `unregister(_:)`: `UnregisterEventHotKey` and forget the handler. Idempotent.
- **Pure helpers** (tested): modifiers → Carbon flags (`controlKey`, `optionKey`, `shiftKey`, `cmdKey`); the
  four-character signature as a `FourCharCode`; action ↔ hot key ID (1-based, stable per `HotKeyAction` case); an
  `OSStatus` → `HotKeyError` mapper.

**`MainAppLoginItem`** (`SMAppService.mainApp`):
- `status` maps `SMAppService.mainApp.status`: `.enabled` → `.enabled`; `.requiresApproval` → `.requiresApproval`;
  `.notRegistered` → `.disabled`; `.notFound` → `.unavailable("macOS can't find this copy of Sway. Move Sway to the
  Applications folder, open it from there, and try again.")`; unknown values → `.unavailable("macOS reported an
  unknown login item state.")`. The mapping is a pure function over an internal mirror enum.
- `setEnabled(true)` calls `register()`, `setEnabled(false)` calls `unregister()`. A thrown error becomes
  `LoginItemError(message:)` with a plain sentence that includes the system's description.
- `openSystemSettings()` calls `SMAppService.openSystemSettingsLoginItems()`.

**Concurrency:** both types are `@MainActor`. `@preconcurrency import Carbon` is allowed (comment why).

**Logging:** category `"system"`: registration outcomes (the shortcut's display string, never other keys) and login
item changes.

**Tests** (pure parts only):
- modifier flag mapping for each modifier and combinations;
- the signature and action IDs (distinct, stable, round-trip);
- the status mapper, including `eventHotKeyExistsErr`;
- `register` with an invalid shortcut throws `.invalidShortcut`;
- the login item status mapper for every case.

**Never in tests:** register a real hot key (it would capture that key combination system-wide while tests run), or
call `SMAppService` `register()` / `unregister()` (it would change the user's login items).

## 7. App entry point and composition (orchestrator-owned)

`Sway/SwayApp.swift`:
```swift
@main struct SwayApp: App {
    @State private var model = AppComposition.makeModel()
    var body: some Scene { SwayScenes(model: model) }
}
```
`Sway/AppComposition.swift` is the only place that names concrete types:
```swift
let camera = CameraCaptureService()
let poseSource = LivePoseSource(frameSource: camera, estimator: VisionPoseEstimator())
AppModel(camera: camera, poseSource: poseSource, displays: ScreenDisplayTracker(),
         traceStore: FileTraceStore(), analyzer: SeparabilityAnalyzer(),
         engine: PoseSwitchEngine(), focus: AXFocusController(),
         hotKeys: CarbonHotKeyCenter(), loginItem: MainAppLoginItem())
```

## 8. Concurrency (Swift 6 language mode, complete checking)

- Zero concurrency warnings.
- The deployment target is **macOS 14**, so `Synchronization.Mutex` (macOS 15) is unavailable. Use
  `OSAllocatedUnfairLock` (from `os`), actors, or private serial `DispatchQueue`s.
- `@unchecked Sendable` is allowed only on a type whose mutable state is fully protected. Add a comment
  saying what protects it. `nonisolated(unsafe)` is not allowed.
- AppKit and SwiftUI work stays on `@MainActor`. Never use `DispatchQueue.main.sync`.
- `@preconcurrency import` is allowed only for Apple frameworks that need it. Comment why.
- Every `AsyncStream` continuation is finished on stop or cancel. Nothing leaks a running camera.

## 9. Naming and code conventions

- No type may share its module's name. Protocols are capability nouns (`FrameSource`, `TraceStoring`).
  Concrete types are descriptive (`CameraCaptureService`).
- One primary type per file, with the file named after it.
- Formatting: 4-space indent, 120 columns. `xcrun swift-format` with the repo's `.swift-format` must be clean.
- Doc comments (`///`) on every public symbol and on non-obvious internal logic.
- No force unwraps or `try!` outside tests. No `print`; use `SwayLog.logger(category:)` with categories
  `camera`, `pose`, `traces`, `displays`, `ui`, `engine`, `focus`, `tracking` (the M4 loop in `SwayUI`), `system`.
- `UserDefaults` keys are prefixed `sway.`. User-facing strings are plain English, sentence case.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) and are named for the behavior.

## 10. Entitlements, Info.plist, signing, permissions (orchestrator-owned)

- **Entitlements** (`Config/Sway.entitlements`): `com.apple.security.device.camera` only. No App Sandbox
  (the Accessibility API in M3 needs it off). No network entitlements.
- **Info.plist** (generated from build settings):
  - `LSUIElement = YES`;
  - `NSCameraUsageDescription`;
  - bundle ID `com.avimal5000.sway`, version 0.1.0 (1), category productivity.
- **Signing:** manual, "Apple Development", team `WNW4M84Z3U`, hardened runtime on.
  - Verification builds use `CODE_SIGNING_ALLOWED=NO`.
  - A stable signature keeps the TCC grants across rebuilds.
- **Release signing (M8, `scripts/release.sh`, `.github/workflows/release.yml`):** the release build uses
  `CODE_SIGNING_ALLOWED=NO`, then signs the app once with `codesign --options runtime --entitlements
  Config/Sway.entitlements`: with a "Developer ID Application" identity and a timestamp, or ad hoc (`-`) when there is
  none. The DMG is signed with the same identity, notarized with `notarytool`, and stapled. The version comes from
  the `vX.Y.Z` tag. Certificate and credentials live only in repository secrets (`MACOS_CERTIFICATE_P12_BASE64`,
  `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`). The script runs
  `scripts/audit-privacy.sh` on the built app. There is no auto-update (SPEC D48). See docs/RELEASING.md.
- **Runtime permissions:**
  - Camera (M1).
  - Accessibility (M3). It needs no entitlement or Info.plist key. The grant is tied to the code signature, so
    unsigned verification builds never keep it.
  - No Screen Recording is needed: window owners and bounds from `CGWindowList` don't require it, and titles
    come from Accessibility.
  - No Input Monitoring is needed (M4): the Focus Lock shortcut is a Carbon hot key, which macOS delivers without
    any permission.
  - Login item (M5): `SMAppService.mainApp` needs no entitlement. macOS may ask the user to approve it in System
    Settings > General > Login Items, and it works reliably only for a copy of the app in `/Applications`.

## 11. Privacy rules (enforced by `scripts/privacy-guard.sh` in CI)

The shipped code in `Sway/` and `SwayCore/Sources/` may not mention these, not even in comments:
- networking: `URLSession`, `URLRequest`, `NSURLConnection`, `Network` / `NW*`, sockets, `WebKit`;
- image or video persistence: `AVAssetWriter`, `AVCaptureMovieFileOutput`, `AVCapturePhotoOutput`,
  `CGImageDestination`, `pngData` / `jpegData` / `tiffRepresentation`, etc.
- cursor movement or input events (M3, PLAN.md "the cursor never moves"): `CGWarpMouseCursorPosition`,
  `CGDisplayMoveCursorToPoint`, `CGAssociateMouseAndMouseCursorPosition`, `CGEventPost`,
  `CGEventCreateMouseEvent`, `CGEventCreateKeyboardEvent`, event taps, `NSEvent` global monitors, and IOKit HID
  input (`IOHIDManager`). Local monitors inside Sway's own windows are fine (the gate overlay's Esc and, in M5, the
  shortcut recorder while it records). The Carbon hot key (`RegisterEventHotKey`) is allowed: macOS delivers only
  the registered combination;
- private window-server or Accessibility APIs: `_AXUIElementGetWindow`, `CGSSetFrontProcess`,
  `_SLPSSetFrontProcess`, and similar.

Only numeric traces, only in DEBUG. No analytics or crash reporting.

## 12. Testing rules

Tests must **never**:
- touch the camera or request any permission;
- write outside a unique folder under `FileManager.default.temporaryDirectory`;
- access the network;
- depend on the number of connected displays;
- sleep for more than about 1 s in total. Use injected clocks or `speed: 0`.
- prompt for Accessibility, or raise, activate, or focus any window (`requestTrust()` and
  `focus(display:in:)` are off limits);
- run real Vision unguarded: tests that do skip when `CI` is set.
- register a real global hot key, or call `SMAppService` `register()` / `unregister()` (M4, M5);
- leave files outside `temporaryDirectory`. A `UserDefaults` suite in tests uses an absolute path under
  `temporaryDirectory` as its suite name (stored as `<path>.plist`); a plain name leaves a file in
  `~/Library/Preferences`.

Tests must cover all non-UI logic in the module.

## 13. Changing this contract

Only the orchestrator edits CONTRACT.md, SwayModels, Package.swift, and the app target. Builders who need a
change stop and report it with the exact proposed diff.
