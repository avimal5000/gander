import Foundation
import SwayModels

/// Wording and slider values for the Switching section of Settings (SPEC F21, D31). Pure.
enum SensitivityPresentation {
    /// The hold time slider moves in steps of this many seconds.
    static let dwellStep = 0.05

    /// The names of the five confidence steps, "Relaxed" to "Strict".
    static let confidenceNames = ["Relaxed", "Easy", "Balanced", "Firm", "Strict"]

    /// The confidence slider's values.
    static let confidenceRange: ClosedRange<Double> = 0...Double(SwitchSensitivity.confidenceMargins.count - 1)

    /// `value` on the 0.05 s grid and inside the allowed range.
    static func snappedDwell(_ value: Double) -> Double {
        let snapped = (value / dwellStep).rounded() * dwellStep
        return min(max(snapped, SwitchSensitivity.dwellRange.lowerBound), SwitchSensitivity.dwellRange.upperBound)
    }

    /// "0.40 s".
    static func dwellText(_ dwell: Double) -> String {
        "\(Formatting.twoDecimals(dwell)) s"
    }

    /// The name of a confidence step; out-of-range levels use the nearest step.
    static func confidenceName(_ level: Int) -> String {
        confidenceNames[min(max(level, 0), confidenceNames.count - 1)]
    }
}
