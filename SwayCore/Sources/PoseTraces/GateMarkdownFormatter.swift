import Foundation
import SwayModels

/// Renders a `GateAnalysis` as the Markdown pasted into `docs/decisions/0001-m1-head-pose-gate.md`.
enum GateMarkdownFormatter {
    static func render(analysis: GateAnalysis, trace: PoseTrace) -> String {
        var lines: [String] = [
            "## M1 head-pose gate result",
            "",
            "- Date: \(dateText(trace.createdAt))",
            "- Camera: \(trace.cameraName ?? "unknown")",
            "- Displays: \(displaysText(trace.layout))",
            "- Overall verdict: **\(label(analysis.overall))**\(bestFeatureText(analysis.bestFeatureSet))",
            "- Thresholds: \(thresholdsText(analysis.thresholds))",
        ]
        for report in analysis.reports {
            lines.append("")
            lines.append(contentsOf: section(for: report))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Header bullets

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func displaysText(_ layout: DisplayLayout?) -> String {
        guard let layout, !layout.displays.isEmpty else { return "unknown (no layout recorded)" }
        return layout.displays.map { display in
            let width = Int(display.frame.width.rounded())
            let height = Int(display.frame.height.rounded())
            return "\(display.name) (\(width)x\(height) pt\(display.isBuiltIn ? ", built-in" : ""))"
        }
        .joined(separator: ", ")
    }

    private static func bestFeatureText(_ featureSet: PoseFeatureSet?) -> String {
        featureSet.map { " (best feature set: \(title($0)))" } ?? ""
    }

    private static func thresholdsText(_ thresholds: GateThresholds) -> String {
        "GO needs d′ ≥ \(thresholds.goDPrime.oneDecimal), accuracy ≥ \(thresholds.goAccuracy.percentOneDecimal)%, "
            + "face detection ≥ \(thresholds.goFaceDetectionRate.percentOneDecimal)%; "
            + "MARGINAL needs d′ ≥ \(thresholds.marginalDPrime.oneDecimal), "
            + "accuracy ≥ \(thresholds.marginalAccuracy.percentOneDecimal)%, "
            + "face detection ≥ \(thresholds.marginalFaceDetectionRate.percentOneDecimal)%; "
            + "at least \(thresholds.minFaceSamplesPerDisplay) face samples per display; "
            + "standard deviations floored at \(thresholds.minStd.oneDecimal)°."
    }

    // MARK: - Per feature set

    private static func section(for report: SeparabilityReport) -> [String] {
        var lines = ["### \(title(report.featureSet)) — \(label(report.verdict))", ""]

        if report.displays.isEmpty {
            lines.append("No labeled displays were recorded.")
        } else {
            lines.append("| Display | Frames | Face % | Mean yaw | Mean pitch | Std yaw | Std pitch |")
            lines.append("|---|---:|---:|---:|---:|---:|---:|")
            for display in report.displays {
                let cells = [
                    cell(display.displayName),
                    "\(display.frameCount)",
                    display.faceDetectionRate.percentOneDecimal,
                    display.meanX.oneDecimal,
                    display.meanY.oneDecimal,
                    display.stdX.oneDecimal,
                    display.stdY.oneDecimal,
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("")

        if report.pairs.isEmpty {
            lines.append("No display pairs to compare.")
        } else {
            lines.append("| Pair | Mean distance | d′ |")
            lines.append("|---|---:|---:|")
            for pair in report.pairs {
                let name = { (id: DisplayID) in report.displays.first { $0.displayID == id }?.displayName ?? id.rawValue
                }
                let cells = [
                    cell("\(name(pair.first)) vs \(name(pair.second))"),
                    pair.meanDistance.oneDecimal,
                    pair.dPrime.oneDecimal,
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("")

        let accuracy = report.accuracy.map { "\($0.percentOneDecimal)%" } ?? "not available"
        lines.append("Held-out accuracy: \(accuracy)")
        lines.append("")

        if report.notes.isEmpty {
            lines.append("Notes: none.")
        } else {
            lines.append("Notes:")
            lines.append(contentsOf: report.notes.map { "- \($0)" })
        }
        return lines
    }

    // MARK: - Labels

    private static func title(_ featureSet: PoseFeatureSet) -> String {
        switch featureSet {
        case .visionAngles: "Vision angles"
        case .landmarkAngles: "Landmark angles"
        }
    }

    private static func label(_ verdict: GateVerdict) -> String {
        switch verdict {
        case .go: "GO"
        case .marginal: "MARGINAL"
        case .noGo: "NO-GO"
        case .insufficientData: "INSUFFICIENT DATA"
        }
    }

    /// Escapes characters that would break a Markdown table cell.
    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
