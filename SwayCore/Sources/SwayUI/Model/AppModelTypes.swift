import Foundation
import SwayModels

/// `UserDefaults` keys (all prefixed `sway.`).
enum DefaultsKey {
    /// Preferred camera's `CameraDevice.id`; absent means "default (built-in)".
    static let cameraDeviceID = "sway.cameraDeviceID"
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
    case live
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
