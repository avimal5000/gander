import Charts
import SwayModels
import SwiftUI

/// Last ~10 s of yaw vs pitch, plus per-display cluster ellipses once a gate analysis exists.
///
/// The live trail is drawn in a `Canvas` over the chart (`TrailLayer`), not as chart marks: Swift Charts rebuilt and
/// re-rendered all ~150 marks on every camera frame, about a quarter of the Pose Debug window's CPU. The chart itself
/// (axes, clusters, legend) now redraws only when its domain or clusters change.
struct PosePlotView: View {
    @Bindable var model: AppModel

    private var featureSet: PoseFeatureSet { model.plotFeatureSet }

    /// What to say over an empty plot. Landmark angles exist only during the gate test, so a landmark plot of live
    /// poses says so instead of waiting for a face that is already there.
    private func placeholder(trail: [PlotTrail.Point]) -> String? {
        PlotPlaceholder.text(
            featureSet: featureSet,
            hasFacePoints: !model.history.points.isEmpty,
            hasPlottedPoints: !trail.isEmpty,
            isRunning: model.status.isRunning
        )
    }

    private var clusters: [PlotGeometry.ClusterShape] {
        guard let report = model.analysis?.report(for: featureSet) else { return [] }
        return PlotGeometry.ClusterShape.shapes(for: report, labels: model.analysisLabels)
    }

    var body: some View {
        let trail = PlotTrail.points(model.history.points, featureSet: featureSet)
        let clusters = clusters
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
            PlotChart(
                model: model, featureSet: featureSet, clusters: clusters,
                xDomain: PlotGeometry.domain(covering: xs), yDomain: PlotGeometry.domain(covering: ys)
            )
            .equatable()
            .frame(height: 260)
            .overlay {
                if let placeholder = placeholder(trail: trail) {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .accessibilityLabel("Plot of yaw versus pitch over the last ten seconds")
        }
    }
}

/// The chart: axes, cluster ellipses and means, and the legend, with the live trail layered over its plot area.
/// Equatable on everything it draws itself, so a new camera frame (which only moves the trail) skips its body.
private struct PlotChart: View, Equatable {
    let model: AppModel
    let featureSet: PoseFeatureSet
    let clusters: [PlotGeometry.ClusterShape]
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>

    nonisolated static func == (lhs: PlotChart, rhs: PlotChart) -> Bool {
        lhs.model === rhs.model && lhs.featureSet == rhs.featureSet && lhs.clusters == rhs.clusters
            && lhs.xDomain == rhs.xDomain && lhs.yDomain == rhs.yDomain
    }

    var body: some View {
        let colors = PlotColors(labels: clusters.map(\.label))
        Chart {
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
        .chartForegroundStyleScale(domain: colors.domain, range: colors.range)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxisLabel("Yaw (\u{00B0})")
        .chartYAxisLabel("Pitch (\u{00B0})")
        .chartLegend(clusters.isEmpty ? .hidden : .visible)
        .chartOverlay { proxy in
            TrailLayer(model: model, featureSet: featureSet, proxy: proxy)
        }
    }
}

/// The live trail, fading with age, and the newest pose, in one `Canvas` over the chart's plot area. It reads the
/// history itself, so a camera frame redraws only this layer.
private struct TrailLayer: View {
    let model: AppModel
    let featureSet: PoseFeatureSet
    let proxy: ChartProxy

    /// Dot diameters, matching the chart marks they replaced (symbol areas 16 and 120 square points).
    private static let trailDiameter: CGFloat = 4
    private static let newestDiameter: CGFloat = 11

    var body: some View {
        let trail = PlotTrail.points(model.history.points, featureSet: featureSet)
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
            let dots: [(center: CGPoint, opacity: Double)] = trail.compactMap { point in
                guard let position = proxy.position(for: (x: point.x, y: point.y)) else { return nil }
                return (CGPoint(x: plot.minX + position.x, y: plot.minY + position.y), point.opacity)
            }
            Canvas { context, _ in
                context.clip(to: Path(plot))
                for dot in dots {
                    context.fill(
                        Self.circle(at: dot.center, diameter: Self.trailDiameter),
                        with: .color(Color.secondary.opacity(dot.opacity)))
                }
                if let newest = dots.last {
                    context.fill(
                        Self.circle(at: newest.center, diameter: Self.newestDiameter),
                        with: .color(SwayPalette.forest))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func circle(at center: CGPoint, diameter: CGFloat) -> Path {
        Path(
            ellipseIn: CGRect(
                x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
    }
}

/// The plotted trail: recent face poses projected onto a feature set, oldest first. Pure, so it is unit tested.
enum PlotTrail {
    struct Point: Equatable {
        let x: Double
        let y: Double
        /// 1 for the newest pose, fading linearly to 0.15 at the plot window's age.
        let opacity: Double
    }

    /// `history` projected onto `featureSet`; poses without those features are skipped.
    static func points(_ history: [PoseHistoryPoint], featureSet: PoseFeatureSet) -> [Point] {
        guard let newest = history.last?.timestamp else { return [] }
        return history.compactMap { item in
            guard let point = featureSet.point(of: item.pose) else { return nil }
            let age = min(1, max(0, (newest - item.timestamp) / PoseHistory.plotWindow))
            return Point(x: point.x, y: point.y, opacity: 1 - 0.85 * age)
        }
    }
}
