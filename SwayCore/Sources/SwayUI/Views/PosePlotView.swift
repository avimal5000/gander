import Charts
import SwayModels
import SwiftUI

/// Last ~10 s of yaw vs pitch, plus per-display cluster ellipses once a gate analysis exists.
struct PosePlotView: View {
    @Bindable var model: AppModel

    private var featureSet: PoseFeatureSet { model.plotFeatureSet }

    /// Recent face poses projected onto the chosen features, oldest first, with a fade-by-age opacity.
    private var trail: [TrailPoint] {
        let points = model.history.points
        guard let newest = points.last?.timestamp else { return [] }
        return points.compactMap { item in
            guard let point = featureSet.point(of: item.pose) else { return nil }
            let age = min(1, max(0, (newest - item.timestamp) / PoseHistory.plotWindow))
            return TrailPoint(id: item.id, x: point.x, y: point.y, opacity: 1 - 0.85 * age)
        }
    }

    private var clusters: [PlotGeometry.ClusterShape] {
        guard let report = model.analysis?.report(for: featureSet) else { return [] }
        return PlotGeometry.ClusterShape.shapes(for: report, labels: model.analysisLabels)
    }

    var body: some View {
        let trail = trail
        let clusters = clusters
        let colors = PlotColors(labels: clusters.map(\.label))
        let xs = trail.map(\.x) + clusters.flatMap { $0.outline.map(\.x) }
        let ys = trail.map(\.y) + clusters.flatMap { $0.outline.map(\.y) }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 10 s: yaw vs pitch")
                    .font(.headline)
                Spacer()
                Picker("Features", selection: $model.plotFeatureSet) {
                    ForEach(PoseFeatureSet.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            Chart {
                clusterMarks(clusters)
                trailMarks(trail)
            }
            .chartForegroundStyleScale(domain: colors.domain, range: colors.range)
            .chartXScale(domain: PlotGeometry.domain(covering: xs))
            .chartYScale(domain: PlotGeometry.domain(covering: ys))
            .chartXAxisLabel("Yaw (\u{00B0})")
            .chartYAxisLabel("Pitch (\u{00B0})")
            .chartLegend(clusters.isEmpty ? .hidden : .visible)
            .frame(height: 260)
            .overlay {
                if trail.isEmpty {
                    Text(model.status.isRunning ? "Waiting for a face\u{2026}" : "Turn the camera on to see live pose")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Plot of yaw versus pitch over the last ten seconds")
        }
    }

    @ChartContentBuilder
    private func clusterMarks(_ clusters: [PlotGeometry.ClusterShape]) -> some ChartContent {
        ForEach(clusters) { cluster in
            ForEach(cluster.outline) { point in
                LineMark(
                    x: .value("Yaw", point.x),
                    y: .value("Pitch", point.y),
                    series: .value("Cluster", cluster.label)
                )
                .foregroundStyle(by: .value("Display", cluster.label))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            PointMark(x: .value("Yaw", cluster.meanX), y: .value("Pitch", cluster.meanY))
                .symbol(.cross)
                .symbolSize(90)
                .foregroundStyle(by: .value("Display", cluster.label))
        }
    }

    @ChartContentBuilder
    private func trailMarks(_ trail: [TrailPoint]) -> some ChartContent {
        ForEach(trail) { point in
            PointMark(x: .value("Yaw", point.x), y: .value("Pitch", point.y))
                .symbolSize(16)
                .foregroundStyle(Color.secondary)
                .opacity(point.opacity)
        }
        if let latest = trail.last {
            PointMark(x: .value("Yaw", latest.x), y: .value("Pitch", latest.y))
                .symbolSize(120)
                .foregroundStyle(SwayPalette.forest)
        }
    }

    private struct TrailPoint: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let opacity: Double
    }
}
