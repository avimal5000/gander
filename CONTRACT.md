# Sway: Engineering Contract (phase M0 + M1)

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
| `SwayUI` | builder-ui | `AppModel`, all scenes and views, gate test flow, overlays | + SwiftUI, AppKit, Charts, Observation |

Planned for later milestones (do **not** create now): `CalibrationModel` (M2), `SwitchDecider` (M2),
`WindowTracker` (M3), `FocusController` (M3), `SwaySettings` (Settings/Permissions/Hotkey, M3–M5),
`TrackingPipeline` (M4). They will follow the same rules.

## 3. Dependency rules

- Every feature module depends **only** on `SwayModels`, plus Apple system frameworks from the table above.
- No module imports another feature module. Cross-module collaboration goes through `SwayModels` protocols,
  and the app target injects concrete types (§7).
- Zero third-party dependencies. No networking frameworks (§11).

## 4. Build and test commands

The Command Line Tools toolchain cannot run `swift test` on this machine, so always set `DEVELOPER_DIR`.
`SWAY_MODULE` makes the manifest declare only `SwayModels` plus your module, which isolates you from
siblings that are mid-edit. The per-module scratch path stops parallel builds from blocking each other.

```bash
cd /Users/avimalhotra/Documents/Sway/SwayCore
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SWAY_MODULE=<Module> swift build --scratch-path .build-agents/<Module>
SWAY_MODULE=<Module> swift test  --scratch-path .build-agents/<Module>
# format + lint your own files (config: /Users/avimalhotra/Documents/Sway/.swift-format)
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
| `PoseSource.swift` | `PoseSourceConfiguration`, `PoseSourceEvent`, protocol `PoseSource`, protocol `PoseEstimating` |
| `Displays.swift` | `DisplayID`, `DisplayInfo`, `DisplayLayout` (sorting + fingerprint), protocol `DisplayProviding` (`@MainActor`) |
| `Traces.swift` | `TraceSegment`, `PoseTrace`, `TraceStoreError`, protocol `TraceStoring` |
| `Separability.swift` | `PoseFeatureSet`, `DisplayPoseStats`, `PairSeparation`, `GateVerdict`, `GateThresholds`, `SeparabilityReport`, `GateAnalysis`, `DisplayClassification`, protocol `SeparabilityAnalyzing` |
| `SwayPolicy.swift` | `SwayPolicy` constants, `SwayLog.logger(category:)` |

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

### 6.2 `PoseEstimator` (builder-pose)

**Public API (exact):**
```swift
public final class VisionPoseEstimator: PoseEstimating { public init() }
public final class LivePoseSource: PoseSource {
    public init(frameSource: any FrameSource, estimator: any PoseEstimating)
}
```

**`VisionPoseEstimator.estimate(_:)`:**
1. Create a `VNImageRequestHandler(cvPixelBuffer:orientation: .up, options: [:])`. Run
   `VNDetectFaceRectanglesRequest` (revision 3 or the latest available; it provides roll, yaw, and pitch)
   and pick the observation with the largest bounding-box area. No face → `nil`.
2. Run `VNDetectFaceLandmarksRequest` on the same handler with `inputFaceObservations = [largest]`.
3. Fill `HeadPose`:
   - `yaw`, `pitch`, `roll`: radians to degrees. If pitch is `nil`, use 0 and log once.
   - `faceConfidence`: the observation's confidence.
   - `faceBounds`: the bounding box.
   - `landmarkYaw` and `landmarkPitch`: from a **pure, unit-tested** geometry function over landmark points
     (normalized to the face box). It uses the eye centers (pupils if present, else eye-region centroids)
     and the nose tip (from `nose` / `noseCrest`). The result must be continuous, about 0 when facing the
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
     ...)`. The frame handler runs the estimator synchronously and yields
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
  - Vision on a blank 640×480 buffer returns `nil` without crashing.

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
counts as −1), then `allCases` order. `classify(_:using:)` applies step 4 to `report.displays` with
`minStd = GateThresholds.default.minStd`. It returns `nil` when the pose lacks the report's features or the
report has no displays; `runnerUpDistance` is `nil` with only one display.

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
Otherwise use system fonts and controls; the app accent color is already forest/sage. Support light and
dark mode.

**Charts:** Swift Charts (system framework) or `Canvas`. Show no video and no camera preview (SPEC D9).

**Tests (no real camera or screens):**
- gate session sequencing, phase timing, labeling, cancel, and trace assembly;
- `AppModel` with fakes for every protocol: start/stop updates the status, events update the latest
  pose/fps, the permission-denied path, and the gate run producing an analysis via a fake analyzer;
- camera selection persistence via a `UserDefaults(suiteName:)` test suite.

Add `#Preview`s with fake dependencies where useful. Fakes live in the test target or in `#if DEBUG`
internal files.

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
         traceStore: FileTraceStore(), analyzer: SeparabilityAnalyzer())
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
  `camera`, `pose`, `traces`, `displays`, `ui`.
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
- **Runtime permissions:**
  - M1: Camera only.
  - Later: Accessibility (M3).
  - No Screen Recording is needed, since window bounds via `CGWindowList` don't require it.

## 11. Privacy rules (enforced by `scripts/privacy-guard.sh` in CI)

The shipped code in `Sway/` and `SwayCore/Sources/` may not mention these, not even in comments:
- networking: `URLSession`, `URLRequest`, `NSURLConnection`, `Network` / `NW*`, sockets, `WebKit`;
- image or video persistence: `AVAssetWriter`, `AVCaptureMovieFileOutput`, `AVCapturePhotoOutput`,
  `CGImageDestination`, `pngData` / `jpegData` / `tiffRepresentation`, etc.

Only numeric traces, only in DEBUG. No analytics or crash reporting.

## 12. Testing rules

Tests must **never**:
- touch the camera or request any permission;
- write outside a unique folder under `FileManager.default.temporaryDirectory`;
- access the network;
- depend on the number of connected displays;
- sleep for more than about 1 s in total. Use injected clocks or `speed: 0`.

Tests must cover all non-UI logic in the module.

## 13. Changing this contract

Only the orchestrator edits CONTRACT.md, SwayModels, Package.swift, and the app target. Builders who need a
change stop and report it with the exact proposed diff.
