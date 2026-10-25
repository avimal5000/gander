import Foundation
import SwayModels

/// Number and text formatting shared by the views, kept pure so it can be unit tested.
enum Formatting {
    /// Placeholder for a missing value.
    static let missing = "\u{2014}"

    /// A signed angle with one decimal, for example `+12.3°`; the placeholder for `nil`.
    static func degrees(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%+.1f\u{00B0}", value)
    }

    /// An unsigned number with one decimal.
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// A 0...1 fraction as a percentage with one decimal; the placeholder for `nil`.
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return missing }
        return String(format: "%.1f%%", fraction * 100)
    }

    /// A 0...1 fraction as a whole-number percentage.
    static func wholePercent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    /// Frames per second with one decimal.
    static func fps(_ value: Double) -> String {
        String(format: "%.1f fps", value)
    }

    /// Duration in whole seconds, for example `26 s`.
    static func seconds(_ value: TimeInterval) -> String {
        "\(Int(value.rounded())) s"
    }
}

extension GateVerdict {
    /// Short uppercase title for badges.
    var title: String {
        switch self {
        case .go: "GO"
        case .marginal: "MARGINAL"
        case .noGo: "NO-GO"
        case .insufficientData: "INSUFFICIENT DATA"
        }
    }

    /// One-sentence reading of the verdict.
    var explanation: String {
        switch self {
        case .go: "Head pose separates your displays reliably."
        case .marginal: "Separation is borderline. Review the notes below before deciding."
        case .noGo: "Head pose alone does not reliably separate these displays."
        case .insufficientData: "Not enough face samples to decide. Check lighting and framing, then run again."
        }
    }
}

extension PoseFeatureSet {
    /// Name shown in pickers and headings.
    var title: String {
        switch self {
        case .visionAngles: "Vision angles"
        case .landmarkAngles: "Landmark proxy"
        }
    }

    /// Short name for compact segmented controls.
    var shortTitle: String {
        switch self {
        case .visionAngles: "Vision"
        case .landmarkAngles: "Landmarks"
        }
    }

    /// Reads this feature set's (yaw-like, pitch-like) pair from a pose; `nil` when unavailable.
    func point(of pose: HeadPose) -> (x: Double, y: Double)? {
        switch self {
        case .visionAngles:
            return (pose.yaw, pose.pitch)
        case .landmarkAngles:
            guard let x = pose.landmarkYaw, let y = pose.landmarkPitch else { return nil }
            return (x, y)
        }
    }
}
