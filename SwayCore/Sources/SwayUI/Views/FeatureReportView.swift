import SwayModels
import SwiftUI

/// One feature set's results: per-display stats, pairwise d', accuracy, notes, and a colored scatter plot.
struct FeatureReportView: View {
    let model: AppModel
    let report: SeparabilityReport
    let thresholds: GateThresholds

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(report.featureSet.title)
                    .font(.headline)
                VerdictBadge(verdict: report.verdict)
            }
            accuracyRow
            displayTable
            pairTable
            notes
            scatter
        }
    }

    private func label(for id: DisplayID) -> String {
        model.analysisLabels[id] ?? id.rawValue
    }

    private var accuracyRow: some View {
        HStack(spacing: 6) {
            Text("Held-out accuracy:")
                .foregroundStyle(.secondary)
            Text(Formatting.percent(report.accuracy))
                .font(.body.weight(.semibold).monospacedDigit())
            Text("(GO needs \(Formatting.wholePercent(thresholds.goAccuracy)))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var displayTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Displays").font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    header("Display")
                    header("Frames")
                    header("Face %")
                    header("Mean yaw")
                    header("Mean pitch")
                    header("Std yaw")
                    header("Std pitch")
                }
                Divider()
                ForEach(Array(report.displays.enumerated()), id: \.element.displayID) { index, stats in
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(SwayPalette.seriesColor(at: index)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(label(for: stats.displayID))
                        }
                        number("\(stats.frameCount)")
                        number(Formatting.wholePercent(stats.faceDetectionRate))
                        number(Formatting.degrees(stats.meanX))
                        number(Formatting.degrees(stats.meanY))
                        number(Formatting.oneDecimal(stats.stdX) + "\u{00B0}")
                        number(Formatting.oneDecimal(stats.stdY) + "\u{00B0}")
                    }
                }
            }
        }
        .swayCard()
    }

    private var pairTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display pairs").font(.subheadline.weight(.semibold))
            if report.pairs.isEmpty {
                Text("Fewer than two displays had labeled data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        header("Pair")
                        header("Mean distance")
                        header("d\u{2032}")
                    }
                    Divider()
                    ForEach(Array(report.pairs.enumerated()), id: \.offset) { _, pair in
                        GridRow {
                            Text("\(label(for: pair.first)) / \(label(for: pair.second))")
                            number(Formatting.oneDecimal(pair.meanDistance) + "\u{00B0}")
                            dPrime(pair.dPrime)
                        }
                    }
                }
                Text("GO needs d\u{2032} \u{2265} \(Formatting.oneDecimal(thresholds.goDPrime)) for every pair.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swayCard()
    }

    private func dPrime(_ value: Double) -> some View {
        let (symbol, color): (String, Color) =
            value >= thresholds.goDPrime
            ? ("checkmark.circle.fill", SwayPalette.forest)
            : (value >= thresholds.marginalDPrime
                ? ("exclamationmark.circle.fill", SwayPalette.amber) : ("xmark.circle.fill", SwayPalette.brick))
        return HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(Formatting.oneDecimal(value)).monospacedDigit()
        }
    }

    @ViewBuilder
    private var notes: some View {
        if !report.notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.subheadline.weight(.semibold))
                ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                    Label(note, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .font(.callout)
                }
            }
            .swayCard()
        }
    }

    @ViewBuilder
    private var scatter: some View {
        if let trace = model.analysisTrace {
            VStack(alignment: .leading, spacing: 6) {
                Text("Samples by display").font(.subheadline.weight(.semibold))
                ScatterPlotView(
                    points: PlotGeometry.scatterPoints(
                        in: trace, featureSet: report.featureSet, labels: model.analysisLabels),
                    clusters: PlotGeometry.ClusterShape.shapes(for: report, labels: model.analysisLabels)
                )
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func number(_ text: String) -> some View {
        Text(text).monospacedDigit()
    }
}

/// A small bullet in front of the text.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}")
            configuration.title
        }
    }
}
