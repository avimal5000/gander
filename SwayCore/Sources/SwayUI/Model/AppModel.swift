import AppKit
import Foundation
import Observation
import SwayModels

/// Root observable state and coordinator for the M1 app.
///
/// `AppModel` owns the camera lifecycle (the pose source runs only while the live toggle is on or a gate test is
/// running), consumes the pose event stream, keeps the rolling history for plots, drives the guided gate test
/// through ``GateTestSession``, and holds the latest separability analysis. It only talks to the protocols in
/// `SwayModels`; the app target injects the concrete implementations.
///
/// The logic is split across extensions by concern (camera, permission, gate, analysis, recording, lifecycle), but
/// all stored state lives here so `@Observable` can track it. Properties are module-internal; views treat them as
/// read-only and call the methods.
@MainActor
@Observable
public final class AppModel {
    // MARK: Collaborators

    @ObservationIgnored let camera: any FrameSource
    @ObservationIgnored let poseSource: any PoseSource
    @ObservationIgnored let displays: any DisplayProviding
    @ObservationIgnored let traceStore: any TraceStoring
    @ObservationIgnored let analyzer: any SeparabilityAnalyzing
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let environment: AppModelEnvironment
    @ObservationIgnored let log = SwayLogger.ui

    // MARK: Camera and pose state

    /// Latest lifecycle state reported by the pose source.
    var status: CaptureStatus = .stopped
    /// Camera permission as last read.
    var authorization: CameraAuthorization
    /// Connected video devices; refreshed whenever a menu or window appears.
    var devices: [CameraDevice] = []
    /// The user's preferred camera (`nil` means the default, built-in first). Persisted under `sway.cameraDeviceID`.
    var selectedCameraID: String?
    /// The state of the "live camera" toggle.
    var liveEnabled = false
    /// Name of the camera most recently reported as running.
    var runningCameraName: String?
    /// The explanation or instructions currently shown for camera permission, if any.
    var permissionPrompt: CameraPermissionPrompt?
    /// Most recent pose sample; `nil` when the camera is off.
    var latestSample: PoseSample?
    /// True when the latest sample contains a face. Stored separately so the menu bar icon only updates when this
    /// flips, not at the frame rate.
    var hasFace = false
    /// Rolling 10 s of poses plus the measured frame rate.
    var history = PoseHistory()
    /// Which feature set the debug plot shows.
    var plotFeatureSet: PoseFeatureSet = .visionAngles

    // MARK: Displays

    /// The current display arrangement.
    var layout: DisplayLayout

    // MARK: Analysis

    /// The report on screen and feeding the live guess.
    var analysis: GateAnalysis?
    /// The trace `analysis` was computed from.
    var analysisTrace: PoseTrace?
    var analysisSource: AnalysisSource?
    /// Unique labels for the analysis' displays.
    var analysisLabels: [DisplayID: String] = [:]
    /// Nearest display cluster to the latest pose under the best feature set's report.
    var liveClassification: DisplayClassification?
    /// The feature set tab selected in the report.
    var reportFeatureSet: PoseFeatureSet = .visionAngles

    // MARK: Gate test

    var gateConfiguration = GateTestConfiguration()
    var gateRunState: GateRunState = .idle
    var gateProgress: GateProgress?
    var gateMessage: UserMessage?
    /// True while the gate window should show the report instead of the setup form.
    var isShowingReport = false
    var traceSaveStatus: TraceSaveStatus = .none
    /// True briefly after the Markdown summary was copied.
    var didCopySummary = false

    // MARK: Internal bookkeeping (not observed)

    @ObservationIgnored var streamTask: Task<Void, Never>?
    @ObservationIgnored var streamGeneration = 0
    @ObservationIgnored var cameraOperation: Task<Void, Never>?
    @ObservationIgnored var layoutTask: Task<Void, Never>?
    @ObservationIgnored var pendingIntent: CameraIntent?
    @ObservationIgnored var gateSession: GateTestSession?
    @ObservationIgnored var gateTimerTask: Task<Void, Never>?
    @ObservationIgnored var gateCameraDeadline: TimeInterval = 0
    @ObservationIgnored var copyResetTask: Task<Void, Never>?
    @ObservationIgnored var requestedWindows: Set<String> = []
    @ObservationIgnored var windowRefs: [String: WeakWindow] = [:]
    @ObservationIgnored var notificationObservers: [any NSObjectProtocol] = []
    #if DEBUG
    @ObservationIgnored let recorder = TraceRecorder()
    #endif

    // MARK: Initialization

    /// Creates the coordinator with its injected collaborators.
    ///
    /// - Parameters:
    ///   - camera: camera discovery and permission.
    ///   - poseSource: the live pose stream (camera frames through Vision).
    ///   - displays: the display layout and its changes.
    ///   - traceStore: trace persistence (DEBUG saves, all builds load).
    ///   - analyzer: separability analysis and the live classifier.
    ///   - defaults: where the camera choice is persisted.
    public convenience init(
        camera: any FrameSource,
        poseSource: any PoseSource,
        displays: any DisplayProviding,
        traceStore: any TraceStoring,
        analyzer: any SeparabilityAnalyzing,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            camera: camera,
            poseSource: poseSource,
            displays: displays,
            traceStore: traceStore,
            analyzer: analyzer,
            defaults: defaults,
            environment: .live()
        )
    }

    init(
        camera: any FrameSource,
        poseSource: any PoseSource,
        displays: any DisplayProviding,
        traceStore: any TraceStoring,
        analyzer: any SeparabilityAnalyzing,
        defaults: UserDefaults,
        environment: AppModelEnvironment
    ) {
        self.camera = camera
        self.poseSource = poseSource
        self.displays = displays
        self.traceStore = traceStore
        self.analyzer = analyzer
        self.defaults = defaults
        self.environment = environment
        self.authorization = camera.authorizationStatus()
        self.selectedCameraID = defaults.string(forKey: DefaultsKey.cameraDeviceID)
        self.layout = displays.currentLayout
        self.devices = camera.availableDevices()

        environment.overlay.onCancelRequested = { [weak self] in
            self?.cancelGateTest(reason: "Gate test cancelled.")
        }
        observeApplicationNotifications()
        observeDisplayLayouts()
    }

    // MARK: Derived state

    /// Measured samples per second over the last 2 s.
    var fps: Double { history.fps }

    /// SF Symbol for the menu bar label.
    var menuBarSymbol: String { status.menuBarSymbol(hasFace: hasFace) }

    /// Name of the camera in use or about to be used.
    var currentCameraName: String? {
        status.device?.name
            ?? runningCameraName
            ?? devices.first(where: { $0.id == selectedCameraID })?.name
            ?? devices.first(where: \.isBuiltIn)?.name
    }

    /// State text plus camera name for the menu status line.
    var statusLine: String { status.statusLine(cameraName: currentCameraName) }

    /// True when the camera session exists (running, starting, suspended, or recovering).
    var isCameraActive: Bool { streamTask != nil }

    /// Re-reads the camera list and permission. Called whenever a menu or window appears.
    func refreshEnvironment() {
        devices = camera.availableDevices()
        authorization = camera.authorizationStatus()
        if authorization == .authorized, permissionPrompt == .denied || permissionPrompt == .restricted {
            permissionPrompt = nil
        }
    }

    // MARK: Window bookkeeping

    /// Records that the user asked for a window, so the launch guard lets it appear.
    func noteWindowRequested(_ id: String) {
        requestedWindows.insert(id)
        refreshEnvironment()
    }

    /// True if the user asked for window `id` and that window has not closed since. The launch guard reveals a
    /// requested window and closes any other.
    func hasWindowRequest(_ id: String) -> Bool {
        requestedWindows.contains(id)
    }

    /// Returns whether `id` was requested, and clears the request. The launch guard calls this when the window
    /// disappears, so the next appearance nobody asked for is suppressed again.
    func consumeWindowRequest(_ id: String) -> Bool {
        requestedWindows.remove(id) != nil
    }

    /// Remembers the `NSWindow` hosting window `id` (weakly) so the guard can hide and reveal it.
    func register(window: NSWindow, id: String) {
        windowRefs[id] = WeakWindow(window)
    }

    /// Makes window `id` fully visible again after the launch guard hid it.
    func revealWindow(_ id: String) {
        windowRefs[id]?.window?.alphaValue = 1
    }
}

/// A weak reference to an `NSWindow`.
@MainActor
final class WeakWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }
}
