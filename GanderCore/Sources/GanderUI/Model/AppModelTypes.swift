import Foundation
import GanderModels

/// `UserDefaults` keys (all prefixed `gander.`).
enum DefaultsKey {
    /// Preferred camera's `CameraDevice.id`; absent means "default (built-in)".
    static let cameraDeviceID = "gander.cameraDeviceID"
    /// The pre-library single `CalibrationProfile` (SPEC D17). Read once at launch to migrate it, then removed.
    static let calibrationProfile = "gander.calibrationProfile"
    /// The `CalibrationLibrary`, as JSON with ISO-8601 dates (SPEC D25).
    static let calibrationLibrary = "gander.calibrationLibrary"
    /// Whether the user last left Tracking on (`Bool`, SPEC D23). Written only by the user's own choices.
    static let trackingEnabled = "gander.trackingEnabled"
    /// The `SwitchSensitivity`, as JSON (SPEC D31). Values saved before D49 have no `cooldown`.
    static let switchSensitivity = "gander.switchSensitivity"
    /// The Focus Lock `HotKeyShortcut` as JSON; empty `Data` means no shortcut, an absent key means the default.
    static let focusLockShortcut = "gander.focusLockShortcut"
    /// The accent the user chose, `"gander"` or `"system"`; absent means Gander green (SPEC D35).
    static let accentChoice = "gander.accentChoice"
    /// Whether the edge glow follows a switch (`Bool`); absent means on (SPEC D38).
    static let edgeGlowEnabled = "gander.edgeGlowEnabled"
    /// Whether the shortcut shows the Focus Lock notice (`Bool`); absent means on (SPEC D39).
    static let focusLockNoticeEnabled = "gander.focusLockNoticeEnabled"
}

/// What the camera permission banner should currently say.
enum CameraPermissionPrompt: Equatable {
    /// Access has not been asked for yet: explain why, then trigger the system prompt.
    case explanation
    /// The user denied access: show how to enable it.
    case denied
    /// A profile or parental control forbids access.
    case restricted
}

/// The action to resume once the user has granted camera access.
enum CameraIntent: Equatable {
    case tracking
    case gateTest
}

/// Where a gate test run is in its life.
enum GateRunState: Equatable {
    case idle
    /// Waiting for the camera to start delivering frames.
    case startingCamera
    /// The session is settling or holding.
    case running
}

/// A short message for the user, shown inline in a window.
struct UserMessage: Equatable {
    enum Kind: Equatable {
        case info
        case error
    }

    var kind: Kind
    var text: String

    static func info(_ text: String) -> UserMessage { UserMessage(kind: .info, text: text) }
    static func error(_ text: String) -> UserMessage { UserMessage(kind: .error, text: text) }
}

/// Where the report currently on screen came from.
enum AnalysisSource: Equatable {
    /// A gate test run in this session.
    case gateTest
    /// A trace loaded with "Open Trace…".
    case file(URL)
}

/// What happened to the trace of the last gate test.
enum TraceSaveStatus: Equatable {
    /// Nothing to report (no run yet, or a trace opened from disk).
    case none
    case saved(URL)
    case failed(String)
    /// Release builds never write traces.
    case disabledInRelease
}
