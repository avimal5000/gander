import Foundation
import GanderModels

/// Wording and slider values for the Switching section of Settings (SPEC F21, F35, D31, D49). Pure.
enum SensitivityPresentation {
    /// The hold time slider moves in steps of this many seconds.
    static let dwellStep = 0.05

    /// The pause slider moves in steps of this many seconds.
    static let cooldownStep = 0.05

    /// The names of the five confidence steps, "Relaxed" to "Strict".
    static let confidenceNames = ["Relaxed", "Easy", "Balanced", "Firm", "Strict"]

    /// The confidence slider's values.
    static let confidenceRange: ClosedRange<Double> = 0...Double(SwitchSensitivity.confidenceMargins.count - 1)

    /// `value` on the 0.05 s grid and inside the allowed range.
    static func snappedDwell(_ value: Double) -> Double {
        snapped(value, step: dwellStep, in: SwitchSensitivity.dwellRange)
    }

    /// `value` on the 0.05 s grid and inside the allowed range.
    static func snappedCooldown(_ value: Double) -> Double {
        snapped(value, step: cooldownStep, in: SwitchSensitivity.cooldownRange)
    }

    /// "0.40 s".
    static func dwellText(_ dwell: Double) -> String {
        "\(Formatting.twoDecimals(dwell)) s"
    }

    /// "0.75 s", in the same format as the hold time.
    static func cooldownText(_ cooldown: Double) -> String {
        "\(Formatting.twoDecimals(cooldown)) s"
    }

    /// The name of a confidence step; out-of-range levels use the nearest step.
    static func confidenceName(_ level: Int) -> String {
        confidenceNames[min(max(level, 0), confidenceNames.count - 1)]
    }

    /// The tooltip of "Use Instant timing": "Hold time 0.10 s and pause 0.30 s. Switch confidence stays as it is."
    static var instantHelp: String {
        "Hold time \(dwellText(SwitchSensitivity.instant.dwell)) and pause "
            + "\(cooldownText(SwitchSensitivity.instant.cooldown)). Switch confidence stays as it is."
    }

    /// The log line for new switching settings: "Switching settings: hold 0.10 s, pause 0.30 s, confidence Easy".
    static func logLine(_ sensitivity: SwitchSensitivity) -> String {
        "Switching settings: hold \(dwellText(sensitivity.dwell)), pause \(cooldownText(sensitivity.cooldown)), "
            + "confidence \(confidenceName(sensitivity.confidenceLevel))"
    }

    /// The grid point nearest `value` inside `range`. Rounded to hundredths, so a step of 0.05 gives 0.3 and not
    /// 0.30000000000000004.
    private static func snapped(_ value: Double, step: Double, in range: ClosedRange<Double>) -> Double {
        let onGrid = ((value / step).rounded() * step * 100).rounded() / 100
        return min(max(onGrid, range.lowerBound), range.upperBound)
    }
}
