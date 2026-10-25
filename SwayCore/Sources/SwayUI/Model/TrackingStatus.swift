import SwayModels

/// The one status the menu bar icon and the popover show (SPEC F19). Pure: a function of a snapshot of the model.
///
/// The cases are listed in priority order; the first that matches wins.
enum TrackingStatus: Equatable {
    /// Tracking is on but the camera permission is denied or restricted.
    case cameraBlocked
    /// The camera reported a failure; shown until the next start.
    case cameraFailed
    /// Tracking is off and no calibration or gate test runs.
    case paused
    /// A calibration or gate test runs.
    case calibrating
    /// Fewer than two displays are connected.
    case oneDisplay
    /// No saved calibration fits the connected displays and camera.
    case needsCalibration
    /// Sleep, displays asleep, or the screen is locked.
    case suspended(SuspendReason)
    /// The camera is starting.
    case starting
    /// The camera is interrupted; carries the interruption text.
    case cameraBusy(String)
    case needsAccessibility
    case focusLock
    case tracking
    case noFace

    /// Everything the status depends on, so the rules can be tested without a model.
    struct Snapshot: Equatable {
        var authorization: CameraAuthorization
        var capture: CaptureStatus
        var trackingEnabled: Bool
        /// A calibration or gate test runs, or the Setup window is on its camera check.
        var calibrationRunning: Bool
        var displayCount: Int
        /// A saved calibration fits the connected displays and the camera.
        var hasCalibration: Bool
        var accessibilityTrusted: Bool
        var focusLocked: Bool
        var hasFace: Bool
    }

    /// How alarming the status is, for the dot in the popover.
    enum Tone: Equatable {
        /// Nothing is running, by choice.
        case idle
        /// Working normally.
        case active
        /// Waiting or needs something from the user.
        case attention
        /// Something is broken.
        case problem
    }

    init(_ snapshot: Snapshot) {
        self = Self.settledStatus(snapshot) ?? Self.cameraStatus(snapshot)
    }

    /// Rows 1 to 6 of the table: what the settings and the displays say, before the camera is considered.
    private static func settledStatus(_ snapshot: Snapshot) -> TrackingStatus? {
        let denied = snapshot.authorization == .denied || snapshot.authorization == .restricted
        if snapshot.trackingEnabled, denied { return .cameraBlocked }
        if case .failed = snapshot.capture { return .cameraFailed }
        if snapshot.calibrationRunning { return .calibrating }
        if !snapshot.trackingEnabled { return .paused }
        if snapshot.displayCount < 2 { return .oneDisplay }
        if !snapshot.hasCalibration { return .needsCalibration }
        return nil
    }

    /// Rows 7 to 13: Tracking is on and calibrated, so the camera and Accessibility decide.
    private static func cameraStatus(_ snapshot: Snapshot) -> TrackingStatus {
        switch snapshot.capture {
        case .suspended(let reason):
            return .suspended(reason)
        case .interrupted(let text):
            return .cameraBusy(text)
        case .starting, .stopped, .failed:
            // `.stopped` with Tracking on and a calibration is the moment before the camera starts.
            return .starting
        case .running:
            if !snapshot.accessibilityTrusted { return .needsAccessibility }
            if snapshot.focusLocked { return .focusLock }
            return snapshot.hasFace ? .tracking : .noFace
        }
    }

    /// The status's SF Symbol (SPEC F19), for the popover's status line. The menu bar icon is the Swing mark instead
    /// (`MenuBarGlyph`, SPEC D37).
    var symbol: String {
        switch self {
        case .cameraBlocked, .cameraFailed, .cameraBusy: "exclamationmark.triangle"
        case .paused: "eye.slash"
        case .calibrating: "scope"
        case .oneDisplay: "display"
        case .needsCalibration: "questionmark.circle"
        case .suspended: "pause.circle"
        case .starting: "eye"
        case .needsAccessibility: "hand.raised"
        case .focusLock: "lock.fill"
        case .tracking: "eye.fill"
        case .noFace: "eye.trianglebadge.exclamationmark"
        }
    }

    /// The status line, without the camera name.
    var line: String {
        switch self {
        case .cameraBlocked: "Camera access needed"
        case .cameraFailed: "Camera unavailable"
        case .paused: "Paused"
        case .calibrating: "Calibrating"
        case .oneDisplay: "Only one display"
        case .needsCalibration: "Needs calibration"
        case .suspended(let reason): CaptureStatus.suspended(reason).summary
        case .starting: "Starting camera"
        case .cameraBusy(let text):
            Self.isUsedByAnotherApp(text) ? "Camera busy" : CaptureStatus.interrupted(text).summary
        case .needsAccessibility: "Needs Accessibility"
        case .focusLock: "Focus Lock on"
        case .tracking: "Tracking"
        case .noFace: "No face"
        }
    }

    var tone: Tone {
        switch self {
        case .cameraBlocked, .cameraFailed, .cameraBusy: .problem
        case .paused, .oneDisplay: .idle
        case .calibrating, .needsCalibration, .suspended, .starting, .needsAccessibility: .attention
        case .focusLock, .tracking, .noFace: .active
        }
    }

    /// The camera service words an interruption by another app's use as "Camera is in use by another app".
    static func isUsedByAnotherApp(_ interruption: String) -> Bool {
        interruption.localizedCaseInsensitiveContains("in use by another")
    }
}
