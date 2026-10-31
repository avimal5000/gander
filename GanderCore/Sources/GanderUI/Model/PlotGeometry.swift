import Foundation
import GanderModels

/// Pure geometry and data shaping for the yaw/pitch plots.
enum PlotGeometry {
    /// A point in feature space (degrees).
    struct Point: Identifiable, Equatable {
        let id: Int
        let x: Double
        let y: Double
    }

    /// Points on the axis-aligned ellipse centered at (`meanX`, `meanY`) with semi-axes `k * stdX` and
    /// `k * stdY`. The outline is closed: the last point repeats the first. Returns just the center when both
    /// deviations are zero.
    static func ellipse(
        meanX: Double, meanY: Double, stdX: Double, stdY: Double, k: Double = 2, segments: Int = 48
    ) -> [Point] {
        let radiusX = abs(stdX) * k
        let radiusY = abs(stdY) * k
        guard radiusX > 0 || radiusY > 0, segments >= 3 else {
            return [Point(id: 0, x: meanX, y: meanY)]
        }
        return (0...segments).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(segments)
            return Point(id: index, x: meanX + radiusX * cos(angle), y: meanY + radiusY * sin(angle))
        }
    }

    /// A padded axis domain covering `values`, rounded outward to multiples of `step`, never narrower than
    /// `minimumSpan`. Falls back to `-minimumSpan/2 ... minimumSpan/2` when there is no data.
    static func domain(
        covering values: [Double], padding: Double = 3, step: Double = 5, minimumSpan: Double = 30
    ) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else {
            return (-minimumSpan / 2)...(minimumSpan / 2)
        }
        var lower = ((low - padding) / step).rounded(.down) * step
        var upper = ((high + padding) / step).rounded(.up) * step
        let missing = minimumSpan - (upper - lower)
        if missing > 0 {
            lower -= (missing / 2 / step).rounded(.down) * step
            upper += (missing / 2 / step).rounded(.up) * step
            if upper - lower < minimumSpan { upper = lower + minimumSpan }
        }
        return lower...upper
    }

    /// One labeled scatter point for the gate report.
    struct ScatterPoint: Identifiable, Equatable {
        let id: Int
        let x: Double
        let y: Double
        /// Unique display label (see `DisplayLabeler`).
        let label: String
    }

    /// Labeled face samples of `trace` projected onto `featureSet`, in segment order. Unlabeled segments and
    /// samples without the features are skipped. `labels` maps each display ID to its unique label.
    static func scatterPoints(
        in trace: PoseTrace, featureSet: PoseFeatureSet, labels: [DisplayID: String]
    ) -> [ScatterPoint] {
        var result: [ScatterPoint] = []
        for segment in trace.segments {
            guard let displayID = segment.displayID, let label = labels[displayID] else { continue }
            for sample in segment.samples {
                guard let pose = sample.pose, let point = featureSet.point(of: pose) else { continue }
                result.append(ScatterPoint(id: result.count, x: point.x, y: point.y, label: label))
            }
        }
        return result
    }
}

extension PlotGeometry {
    /// A display's cluster as drawn on a plot: its mean and the mean +/- 2 sigma outline.
    struct ClusterShape: Identifiable, Equatable {
        /// Unique display label.
        let label: String
        let meanX: Double
        let meanY: Double
        let outline: [Point]

        var id: String { label }

        /// One shape per display in `report`, in report order, outlined at two standard deviations.
        static func shapes(for report: SeparabilityReport, labels: [DisplayID: String]) -> [ClusterShape] {
            report.displays.map { stats in
                ClusterShape(
                    label: labels[stats.displayID] ?? stats.displayName,
                    meanX: stats.meanX,
                    meanY: stats.meanY,
                    outline: PlotGeometry.ellipse(
                        meanX: stats.meanX, meanY: stats.meanY, stdX: stats.stdX, stdY: stats.stdY
                    )
                )
            }
        }
    }
}
