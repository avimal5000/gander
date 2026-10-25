import AppKit
import Foundation
import Observation
import SwayModels

/// Root observable state and coordinator for the app.
///
/// `AppModel` owns the camera lifecycle (the pose source runs only while Tracking is on and a calibration fits, or a
/// gate test is running), consumes the pose event stream, keeps the rolling history for plots, drives the guided gate
/// test through ``GateTestSession``, and holds the latest separability analysis. From each analysis it fits a
/// calibration and saves it in the ``CalibrationLibrary``. While Tracking is on, it runs every pose sample through the
/// switch decider and moves real focus when a look is held (``TrackingLoop``), with Focus Lock and its global
/// shortcut. It drives the Focus Test window, the Set Up Sway window (permissions, a camera check, and a guided
/// calibration that reuses the gate machinery), and the Sway Settings window. It only talks to the protocols in
/// `SwayModels`; the app target injects the concrete implementations.
///
/// The logic is split across extensions by concern (camera, permission, gate, analysis, calibration, tracking, focus
/// lock, focus test, setup, settings, recording, lifecycle), but all stored state lives here so `@Observable` can
/// track it.
/// Properties are module-internal; views treat them as read-only and call the methods.
///
/// Performance rule: views that are always alive (the menu popover and the menu bar label) must not read anything
/// that changes at the frame rate. Such state is assigned only when it actually changes (`hasFace`, `lookSummary`,
/// `trackingFocus`), because an `@Observable` setter notifies on every assignment, equal or not.
@MainActor
@Observable
public final class AppModel {
    // MARK: Collaborators

    @ObservationIgnored let camera: any FrameSource
    @ObservationIgnored let poseSource: any PoseSource
    @ObservationIgnored let displays: any DisplayProviding
    @ObservationIgnored let traceStore: any TraceStoring
    @ObservationIgnored let analyzer: any SeparabilityAnalyzing
    @ObservationIgnored let engine: any SwitchEngineMaking
    @ObservationIgnored let focus: any FocusControlling
    @ObservationIgnored let hotKeys: any HotKeyRegistering
    /// Opens Sway at login (the Settings window's General section).
    @ObservationIgnored let loginItem: any LoginItemControlling
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let environment: AppModelEnvironment
    @ObservationIgnored let log = SwayLogger.ui

    // MARK: Camera and pose state

    /// Latest lifecycle state reported by the pose source.
    var status: CaptureStatus = .stopped
    /// Camera permission as last read.
    var authorization: CameraAuthorization
    /// Connected video devices; refreshed whenever a menu or window appears and when a camera connects or disconnects.
    var devices: [CameraDevice] = []
    /// The camera capture would open for `selectedCameraID` right now (`FrameSource.resolvedDevice`), refreshed with
    /// `devices`. Asking the camera service keeps it identical to capture's own rule, so the calibration looked up
    /// while stopped is the one that fits once the camera runs.
    var predictedCameraName: String?
    /// The user's preferred camera (`nil` means the default, built-in first). Persisted under `sway.cameraDeviceID`.
    var selectedCameraID: String?
    /// The Tracking switch: on means tracking, off is Paused with the camera off (SPEC D26). Only the user's own
    /// choices are saved (`setTrackingEnabled`); a camera failure or quitting turns it off in memory alone.
    var trackingEnabled = false
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
    /// The latest pose and frame rate as the text readouts show them, refreshed five times a second
    /// (`LiveReadout`). Only replaced when due, so views reading it update at that rate, not the frame rate.
    var readout = LiveReadout()
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
    /// The feature set `liveClassification` was computed with: the best one, or Vision angles when the pose lacks
    /// the best set's features (landmarks exist only during the gate test).
    var liveGuessFeatureSet: PoseFeatureSet?
    /// The feature set tab selected in the report.
    var reportFeatureSet: PoseFeatureSet = .visionAngles

    // MARK: Gate test

    var gateConfiguration = GateTestConfiguration()
    var gateRunState: GateRunState = .idle
    /// What the run in progress is for; `.gateTest` while none runs.
    var gatePurpose: GatePurpose = .gateTest
    var gateProgress: GateProgress?
    var gateMessage: UserMessage?
    /// True while the gate window should show the report instead of the setup form.
    var isShowingReport = false
    var traceSaveStatus: TraceSaveStatus = .none
    /// True briefly after the Markdown summary was copied.
    var didCopySummary = false

    // MARK: Calibration and tracking

    /// Every saved calibration; persisted under `sway.calibrationLibrary` after each change.
    var library: CalibrationLibrary
    /// The calibration for the connected displays and camera, restricted to the connected displays; `nil` when none
    /// fits (SPEC D25).
    var activeCalibration: CalibrationMatch?
    /// Why the last fit failed, shown in the report view; `nil` after a successful fit.
    var calibrationMessage: UserMessage?
    /// The profile the last successful fit saved, for the report view.
    var lastFittedProfile: CalibrationProfile?
    /// The user's switching settings (SPEC D31).
    var sensitivity: SwitchSensitivity
    /// The decider's output for the latest tracked sample; `nil` before the first sample or after a reset.
    var previewDecision: SwitchDecision?
    /// What the tracking loop believes has keyboard focus (`loop.focusedDisplay`), for the Pose Debug window. The loop
    /// itself is not observed: it changes on every sample.
    var trackingFocus: DisplayID?
    /// True while Sway's own focus request runs (`loop.isFocusing`).
    var isSwitching = false
    /// Sway is in front: the active app with its menu or one of its windows key (SPEC D28).
    var isAppActive = false
    /// The popover's "Looking at" line, assigned only when it changes.
    var lookSummary: LookSummary = .off
    /// The last real switches, newest first, at most ``switchLogLimit``.
    var switchLog: [SwitchLogEntry] = []

    // MARK: Setup window

    /// The Set Up Sway window's flow; `nil` while the window is closed.
    var setupFlow: SetupFlow?
    /// A note under the camera check: "Calibration cancelled.", or why a run ended early.
    var setupMessage: UserMessage?
    /// What the result step says; `nil` outside it.
    var setupResult: SetupResult?
    /// The camera check's hint, refreshed at most five times a second and assigned only when it changes.
    var framingAdvice: FramingAdvice = .noFace

    // MARK: Settings window

    /// The login item as last read (when the Settings window appeared, and after each change).
    var loginItemStatus: LoginItemStatus = .disabled
    /// Why the last login item change failed.
    var loginItemMessage: String?
    /// True while the Focus Lock shortcut recorder listens for a key press.
    var isRecordingShortcut = false
    /// Why the last key press could not be a shortcut.
    var shortcutRecordingHint: String?

    // MARK: Focus Lock

    /// Focus Lock (SPEC D27): the camera stays on and no switch fires. Not saved; off at launch.
    var focusLocked = false
    /// The global shortcut that toggles Focus Lock; `nil` means none.
    var focusLockShortcut: HotKeyShortcut?
    /// Why the shortcut could not be registered, for Settings, and for the menu banner while the chosen shortcut is not
    /// working.
    var shortcutMessage: String?
    /// True while `focusLockShortcut` is registered with the system (it isn't while recording a new one).
    var isShortcutRegistered = false

    // MARK: Focus test

    /// Accessibility permission as last polled (never prompts).
    var isAccessibilityTrusted = false
    /// The last-used window per display as last polled, while the Focus Test window is open. Titles are shown
    /// only, never logged or stored.
    var focusWindows: [DisplayID: WindowSummary] = [:]
    /// The display holding the focused window as last polled; `nil` when unknown.
    var focusedDisplayID: DisplayID?
    var focusActivity: FocusActivity = .idle
    /// Whole seconds left in a "Focus in 3 s" countdown.
    var focusCountdownSeconds = 0
    /// The last focus results, newest first, at most ``focusLogLimit``.
    var focusLog: [FocusLogEntry] = []

    // MARK: Internal bookkeeping (not observed)

    @ObservationIgnored var streamTask: Task<Void, Never>?
    @ObservationIgnored var streamGeneration = 0
    @ObservationIgnored var cameraOperation: Task<Void, Never>?
    @ObservationIgnored var layoutTask: Task<Void, Never>?
    @ObservationIgnored var pendingIntent: CameraIntent?
    /// The configuration the current pose stream was started with; `nil` when no stream runs.
    @ObservationIgnored var activeConfiguration: PoseSourceConfiguration?
    @ObservationIgnored var decider: (any SwitchDeciding)?
    /// The tracking loop's focus bookkeeping. Not observed (it changes per sample); see ``trackingFocus``.
    @ObservationIgnored var loop = TrackingLoop()
    /// The displays focus may move to (`nil` means every calibrated display).
    @ObservationIgnored var trackedTargets: Set<DisplayID>?
    /// Unique labels for the connected displays, so the per-sample path never rebuilds them.
    @ObservationIgnored var displayLabels: [DisplayID: String] = [:]
    /// The enter margin of the current sensitivity, read per sample.
    @ObservationIgnored var enterMargin = SwitchSensitivity.default.switchSettings().enterMargin
    @ObservationIgnored var focusSwitchTask: Task<Void, Never>?
    @ObservationIgnored var isPollingFocus = false
    @ObservationIgnored var trackingTickTask: Task<Void, Never>?
    @ObservationIgnored var trackingPollTask: Task<Void, Never>?
    /// Where the dwell now in progress began, for the latency of the switch it ends in.
    @ObservationIgnored var dwellStart: (display: DisplayID, timestamp: TimeInterval)?
    @ObservationIgnored var nextLogID = 0
    @ObservationIgnored var focusTestVisible = false
    @ObservationIgnored var focusTickTask: Task<Void, Never>?
    @ObservationIgnored var focusRequestTask: Task<Void, Never>?
    @ObservationIgnored var focusPollTask: Task<Void, Never>?
    @ObservationIgnored var focusPollGeneration = 0
    @ObservationIgnored var nextFocusPoll: TimeInterval = 0
    @ObservationIgnored var gateSession: GateTestSession?
    @ObservationIgnored var gateTimerTask: Task<Void, Never>?
    @ObservationIgnored var gateCameraDeadline: TimeInterval = 0
    /// The user chose "Skip for now" on the Accessibility step; the Setup window then no longer asks during this
    /// app run.
    @ObservationIgnored var setupAccessibilitySkipped = false
    @ObservationIgnored var setupTickTask: Task<Void, Never>?
    /// Sample time of the last camera check hint refresh.
    @ObservationIgnored var lastFramingRefresh: TimeInterval?
    @ObservationIgnored var settingsVisible = false
    @ObservationIgnored var copyResetTask: Task<Void, Never>?
    @ObservationIgnored var requestedWindows: Set<String> = []
    @ObservationIgnored var windowRefs: [String: WeakWindow] = [:]
    @ObservationIgnored var notificationObservers: [any NSObjectProtocol] = []
    @ObservationIgnored var workspaceObservers: [any NSObjectProtocol] = []
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
    ///   - engine: fits the calibration profile and makes the switch decider for the preview.
    ///   - focus: last-used windows, focused display, Accessibility trust, and focus requests.
    ///   - hotKeys: registers the Focus Lock shortcut.
    ///   - loginItem: opens Sway at login (used by the Settings window).
    ///   - defaults: where the camera choice, calibrations, Tracking choice, sensitivity, and shortcut are persisted.
    public convenience init(
        camera: any FrameSource,
        poseSource: any PoseSource,
        displays: any DisplayProviding,
        traceStore: any TraceStoring,
        analyzer: any SeparabilityAnalyzing,
        engine: any SwitchEngineMaking,
        focus: any FocusControlling,
        hotKeys: any HotKeyRegistering,
        loginItem: any LoginItemControlling,
        defaults: UserDefaults = .standard
    ) {
        self.init(
            camera: camera,
            poseSource: poseSource,
            displays: displays,
            traceStore: traceStore,
            analyzer: analyzer,
            engine: engine,
            focus: focus,
            hotKeys: hotKeys,
            loginItem: loginItem,
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
        engine: any SwitchEngineMaking,
        focus: any FocusControlling,
        hotKeys: any HotKeyRegistering,
        loginItem: any LoginItemControlling,
        defaults: UserDefaults,
        environment: AppModelEnvironment
    ) {
        self.camera = camera
        self.poseSource = poseSource
        self.displays = displays
        self.traceStore = traceStore
        self.analyzer = analyzer
        self.engine = engine
        self.focus = focus
        self.hotKeys = hotKeys
        self.loginItem = loginItem
        self.defaults = defaults
        self.environment = environment
        self.authorization = camera.authorizationStatus()
        self.selectedCameraID = defaults.string(forKey: DefaultsKey.cameraDeviceID)
        let initialLayout = displays.currentLayout
        let storedLibrary = Self.storedLibrary(in: defaults)
        let storedSensitivity = Self.storedSensitivity(in: defaults)
        self.layout = initialLayout
        self.devices = camera.availableDevices()
        self.predictedCameraName = camera.resolvedDevice(for: defaults.string(forKey: DefaultsKey.cameraDeviceID))?.name
        self.library = storedLibrary.library
        self.sensitivity = storedSensitivity
        self.focusLockShortcut = Self.storedFocusLockShortcut(in: defaults)
        self.trackingEnabled = defaults.bool(forKey: DefaultsKey.trackingEnabled)
        self.isAppActive = environment.isAppActive()
        self.displayLabels = DisplayLabeler.labels(for: initialLayout)
        self.enterMargin = storedSensitivity.switchSettings().enterMargin

        if storedLibrary.migrated { persistLibrary() }
        refreshActiveCalibration(reconcile: false)
        environment.overlay.onCancelRequested = { [weak self] in
            self?.cancelRunningGate()
        }
        observeApplicationNotifications()
        observeDisplayLayouts()
        registerFocusLockShortcut()
        if trackingEnabled {
            // Tracking starts without any window: one reconcile right after launch.
            Task { @MainActor [weak self] in
                await self?.reconcileCamera().value
            }
        }
    }

    // MARK: Derived state

    /// Measured samples per second over the last 2 s.
    var fps: Double { history.fps }

    /// The one status the menu bar icon and popover show (SPEC F19).
    var trackingStatus: TrackingStatus {
        TrackingStatus(
            TrackingStatus.Snapshot(
                authorization: authorization,
                capture: status,
                trackingEnabled: trackingEnabled,
                calibrationRunning: gateRunState != .idle || isSetupUsingCamera,
                displayCount: layout.displays.count,
                hasCalibration: activeCalibration != nil,
                accessibilityTrusted: isAccessibilityTrusted,
                focusLocked: focusLocked,
                hasFace: hasFace
            ))
    }

    /// SF Symbol for the menu bar label.
    var menuBarSymbol: String { trackingStatus.symbol }

    /// Name of the camera in use or about to be used.
    var currentCameraName: String? {
        status.device?.name
            ?? runningCameraName
            ?? predictedCameraName
    }

    /// The status text, plus " · <camera name>" while the camera runs, for the popover.
    var statusLine: String {
        let line = trackingStatus.line
        guard status.isRunning, let name = status.device?.name ?? currentCameraName else { return line }
        return "\(line) \u{00B7} \(name)"
    }

    /// True when the camera session exists (running, starting, suspended, or recovering).
    var isCameraActive: Bool { streamTask != nil }

    /// Re-reads the camera list and permission. Called whenever a menu or window appears, and when a camera connects
    /// or disconnects.
    func refreshEnvironment() {
        let previousAuthorization = authorization
        devices = camera.availableDevices()
        refreshPredictedCamera()
        authorization = camera.authorizationStatus()
        if authorization == .authorized, permissionPrompt == .denied || permissionPrompt == .restricted {
            permissionPrompt = nil
        }
        // The camera that capture would pick may have changed with the device list.
        refreshActiveCalibration()
        // Access granted in System Settings: a Tracking switch left on, blocked, starts the camera now.
        if authorization == .authorized, previousAuthorization != .authorized, wantsCamera, streamTask == nil {
            reconcileCamera()
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
