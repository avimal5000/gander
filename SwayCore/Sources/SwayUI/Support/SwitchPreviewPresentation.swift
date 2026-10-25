import Foundation
import SwayModels

/// Wording for the Switch preview section. Pure functions of model values.
enum SwitchPreviewPresentation {
    static let noProfile = "Run the gate test to calibrate."
    static let stale = "Displays changed since calibration. Run the gate test again to recalibrate."
    static let cameraOff = "Turn the camera on to see the preview."
    static let noSwitches = "No switches yet. Look at another display and hold."

    /// What the pose points at: the nearest display, "No face", or "Looking elsewhere".
    static func classificationText(_ classification: PoseClassification?, name: (DisplayID) -> String) -> String {
        guard let classification else { return "No face" }
        switch classification.kind {
        case .noFace: return "No face"
        case .elsewhere: return "Looking elsewhere"
        case .display: return classification.best.map { "Nearest: \(name($0))" } ?? "No face"
        }
    }

    /// The margin bar's value, 0...1; `nil` unless the pose points at a display.
    static func margin(_ classification: PoseClassification?) -> Double? {
        guard let classification, classification.kind == .display else { return nil }
        return min(1, max(0, classification.margin))
    }

    /// The decider phase: "Watching", "Dwelling on <name>", "Cooling down", or the lock.
    static func phaseText(_ phase: SwitchPhase?, name: (DisplayID) -> String) -> String {
        switch phase {
        case nil, .idle?: "Watching"
        case .dwelling(let display, _)?: "Dwelling on \(name(display))"
        case .coolingDown?: "Cooling down"
        case .locked?: "Focus lock is on"
        }
    }

    /// The dwell progress bar's value, 0...1; `nil` outside a dwell.
    static func dwellProgress(_ phase: SwitchPhase?) -> Double? {
        guard case .dwelling(_, let progress)? = phase else { return nil }
        return min(1, max(0, progress))
    }

    /// "Focus (simulated): <name or Unknown>".
    static func simulatedFocusText(_ focus: DisplayID?, name: (DisplayID) -> String) -> String {
        "Focus (simulated): \(focus.map(name) ?? "Unknown")"
    }

    /// A log line: "Switch to <name> after 0.42 s".
    static func logText(_ entry: SwitchLogEntry) -> String {
        "Switch to \(entry.displayName) after \(Formatting.twoDecimals(entry.latency)) s"
    }
}
