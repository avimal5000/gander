import Foundation

/// Mean and sample covariance (n − 1) of a 2-D point cloud. Covariance is zero when there are fewer than 2 points;
/// the mean of an empty cloud is the origin.
struct ClusterStatistics: Equatable {
    var count: Int
    var meanX: Double
    var meanY: Double
    var varianceXX: Double
    var varianceXY: Double
    var varianceYY: Double

    /// Sample standard deviation along x (0 when `count < 2`).
    var stdX: Double { varianceXX.squareRoot() }
    /// Sample standard deviation along y (0 when `count < 2`).
    var stdY: Double { varianceYY.squareRoot() }

    init(points: [FeaturePoint]) {
        count = points.count
        guard count > 0 else {
            meanX = 0
            meanY = 0
            varianceXX = 0
            varianceXY = 0
            varianceYY = 0
            return
        }
        let n = Double(count)
        meanX = points.reduce(0) { $0 + $1.x } / n
        meanY = points.reduce(0) { $0 + $1.y } / n
        guard count > 1 else {
            varianceXX = 0
            varianceXY = 0
            varianceYY = 0
            return
        }
        var sumXX = 0.0
        var sumXY = 0.0
        var sumYY = 0.0
        for point in points {
            let dx = point.x - meanX
            let dy = point.y - meanY
            sumXX += dx * dx
            sumXY += dx * dy
            sumYY += dy * dy
        }
        varianceXX = sumXX / (n - 1)
        varianceXY = sumXY / (n - 1)
        varianceYY = sumYY / (n - 1)
    }

    /// Variance of the projection of the cloud onto the unit vector `(ux, uy)`: uᵀ Σ u.
    func variance(alongX ux: Double, y uy: Double) -> Double {
        ux * ux * varianceXX + 2 * ux * uy * varianceXY + uy * uy * varianceYY
    }

    /// Separation of two clouds: the distance between the means and the Fisher d′ along the line joining them.
    ///
    /// With `u = (μa − μb) / ‖μa − μb‖`, each class variance along `u` is `max(uᵀ Σ u, minStd²)` and
    /// `d′ = ‖μa − μb‖ / sqrt((σa² + σb²) / 2)`. When the means coincide, d′ is 0.
    static func separation(
        _ a: ClusterStatistics,
        _ b: ClusterStatistics,
        minStd: Double
    ) -> (meanDistance: Double, dPrime: Double) {
        let dx = a.meanX - b.meanX
        let dy = a.meanY - b.meanY
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0 else { return (0, 0) }
        let ux = dx / distance
        let uy = dy / distance
        let floor = minStd * minStd
        let varianceA = max(a.variance(alongX: ux, y: uy), floor)
        let varianceB = max(b.variance(alongX: ux, y: uy), floor)
        return (distance, distance / ((varianceA + varianceB) / 2).squareRoot())
    }
}
