import Foundation
import SwayModels

/// Wording for the Switch preview section. Pure functions of model values.
enum SwitchPreviewPresentation {
    static let noProfile = "Not calibrated yet. Choose Calibrate\u{2026} in the menu."
    static let noMatchingProfile =
        "No saved calibration fits these displays and this camera. Choose Calibrate\u{2026} in the menu."
    static let trackingOff = "Turn Tracking on to see the preview."
    static let noSwitches = "No switches yet. Look at another display and hold."
    static let needsAccessibility = "Accessibility is not granted, so Gander cannot move focus."

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
        case .locked?: "Switching is held"
        }
    }

    /// The dwell progress bar's value, 0...1; `nil` outside a dwell.
    static func dwellProgress(_ phase: SwitchPhase?) -> Double? {
        guard case .dwelling(_, let progress)? = phase else { return nil }
        return min(1, max(0, progress))
    }

    /// "Focus: <name or Unknown>", from the tracking loop's belief about where keyboard focus is.
    static func focusText(_ focus: DisplayID?, name: (DisplayID) -> String) -> String {
        "Focus: \(focus.map(name) ?? "Unknown")"
    }

    /// A log line for a focus request's result. Names the app and the display, never a window title.
    static func logText(for result: FocusResult, display: String, held: TimeInterval) -> String {
        switch result {
        case .focused(let window, _, let milliseconds):
            "Focused \(window.appName) on \(display) in \(milliseconds) ms, held \(Formatting.twoDecimals(held)) s"
        case .noWindow:
            "No window on \(display)"
        case .notTrusted:
            "Accessibility permission needed"
        case .failed(_, let reason):
            "Failed: \(reason)"
        }
    }
}
