import Charts
import SwiftUI

/// Every labeled face sample of a gate test, colored by display, with each cluster's mean +/- 2 sigma outline.
struct ScatterPlotView: View {
    let points: [PlotGeometry.ScatterPoint]
    let clusters: [PlotGeometry.ClusterShape]

    var body: some View {
        let colors = PlotColors(labels: clusters.map(\.label))
        let xs = points.map(\.x) + clusters.flatMap { $0.outline.map(\.x) }
        let ys = points.map(\.y) + clusters.flatMap { $0.outline.map(\.y) }
        Chart {
            ForEach(points) { point in
                PointMark(x: .value("Yaw", point.x), y: .value("Pitch", point.y))
                    .symbolSize(14)
                    .opacity(0.5)
                    .foregroundStyle(by: .value("Display", point.label))
            }
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
            }
        }
        .chartForegroundStyleScale(domain: colors.domain, range: colors.range)
        .chartXScale(domain: PlotGeometry.domain(covering: xs))
        .chartYScale(domain: PlotGeometry.domain(covering: ys))
        .chartXAxisLabel("Yaw (\u{00B0})")
        .chartYAxisLabel("Pitch (\u{00B0})")
        .chartLegend(.visible)
        .frame(height: 300)
        .accessibilityLabel("Scatter plot of yaw versus pitch, colored by display")
    }
}
