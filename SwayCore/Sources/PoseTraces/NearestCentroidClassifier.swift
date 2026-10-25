/// Diagonal z-distance nearest-centroid classifier (CONTRACT.md 6.3, step 4).
///
/// The normalized distance of a point to a cluster is
/// `z = sqrt(((x − meanX) / sX)² + ((y − meanY) / sY)²)` with `sX = max(stdX, minStd)` and likewise `sY`.
/// The cluster with the smallest `z` wins; ties go to the earlier candidate.
struct NearestCentroidClassifier {
    /// A cluster that may win. `index` identifies it to the caller (its position in display order).
    struct Candidate: Equatable {
        var index: Int
        var meanX: Double
        var meanY: Double
        var stdX: Double
        var stdY: Double
    }

    /// The winning candidate and the distances involved.
    struct Match: Equatable {
        var index: Int
        var distance: Double
        /// Distance to the second-nearest candidate; `nil` with a single candidate.
        var runnerUpDistance: Double?
    }

    /// Standard deviations are floored at this many degrees.
    var minStd: Double

    /// Nearest candidate to `point`; `nil` when there are no candidates.
    func classify(_ point: FeaturePoint, among candidates: [Candidate]) -> Match? {
        let ranked =
            candidates
            .map { (index: $0.index, distance: normalizedDistance(from: point, to: $0)) }
            .sorted { ($0.distance, $0.index) < ($1.distance, $1.index) }
        guard let best = ranked.first else { return nil }
        return Match(index: best.index, distance: best.distance, runnerUpDistance: ranked.dropFirst().first?.distance)
    }

    /// The normalized distance `z` from `point` to `candidate`.
    func normalizedDistance(from point: FeaturePoint, to candidate: Candidate) -> Double {
        let sx = max(candidate.stdX, minStd)
        let sy = max(candidate.stdY, minStd)
        let zx = (point.x - candidate.meanX) / sx
        let zy = (point.y - candidate.meanY) / sy
        return (zx * zx + zy * zy).squareRoot()
    }
}
