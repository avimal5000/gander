import Testing

@testable import PoseTraces

@Suite struct ClusterStatisticsTests {
    private func points(_ pairs: [(Double, Double)]) -> [FeaturePoint] {
        pairs.map { FeaturePoint(x: $0.0, y: $0.1) }
    }

    @Test func meansAndSampleCovarianceUseNMinusOne() {
        let stats = ClusterStatistics(points: points([(0, 0), (2, 0), (0, 2), (2, 2)]))
        #expect(stats.count == 4)
        #expect(stats.meanX == 1)
        #expect(stats.meanY == 1)
        // Sum of squared deviations is 4 per axis, divided by n - 1 = 3.
        #expect(abs(stats.varianceXX - 4.0 / 3.0) < 1e-12)
        #expect(abs(stats.varianceYY - 4.0 / 3.0) < 1e-12)
        #expect(abs(stats.varianceXY) < 1e-12)
        #expect(abs(stats.stdX - (4.0 / 3.0).squareRoot()) < 1e-12)
    }

    @Test func fewerThanTwoPointsHaveZeroSpread() {
        let one = ClusterStatistics(points: points([(3, -4)]))
        #expect(one.meanX == 3)
        #expect(one.meanY == -4)
        #expect(one.stdX == 0)
        #expect(one.stdY == 0)

        let none = ClusterStatistics(points: [])
        #expect(none.count == 0)
        #expect(none.meanX == 0)
        #expect(none.stdX == 0)
    }

    @Test func dPrimeMatchesHandComputedCorrelatedCase() {
        // Both classes lie along the diagonal: Σ = [[1, 1], [1, 1]] (points (0,0),(1,1),(2,2) and shifted copy).
        // Means (1, 1) and (4, 5): distance 5, u = (-0.6, -0.8), uᵀΣu = (u1 + u2)² = 1.96, so d′ = 5 / 1.4.
        let a = ClusterStatistics(points: points([(0, 0), (1, 1), (2, 2)]))
        let b = ClusterStatistics(points: points([(3, 4), (4, 5), (5, 6)]))
        let separation = ClusterStatistics.separation(a, b, minStd: 0.5)
        #expect(abs(separation.meanDistance - 5) < 1e-12)
        #expect(abs(separation.dPrime - 5.0 / 1.4) < 1e-12)
    }

    @Test func dPrimeMatchesHandComputedAxisAlignedCase() {
        // Means (0, 0) and (10, 0); each class has x variance 2 along the joining line: d′ = 10 / sqrt(2).
        let a = ClusterStatistics(points: points([(-1, 0), (1, 0)]))
        let b = ClusterStatistics(points: points([(9, 0), (11, 0)]))
        let separation = ClusterStatistics.separation(a, b, minStd: 0.5)
        #expect(abs(separation.meanDistance - 10) < 1e-12)
        #expect(abs(separation.dPrime - 10 / 2.0.squareRoot()) < 1e-12)
    }

    @Test func dPrimeFloorsTheVarianceAtMinStdSquared() {
        // Class b has no spread at all, so its variance is floored at 0.5² = 0.25: d′ = 10 / sqrt((2 + 0.25) / 2).
        let a = ClusterStatistics(points: points([(-1, 0), (1, 0)]))
        let b = ClusterStatistics(points: points([(10, 0), (10, 0)]))
        let separation = ClusterStatistics.separation(a, b, minStd: 0.5)
        #expect(abs(separation.dPrime - 10 / (2.25 / 2).squareRoot()) < 1e-12)
    }

    @Test func coincidentMeansGiveZeroDPrime() {
        let a = ClusterStatistics(points: points([(-1, 0), (1, 0)]))
        let b = ClusterStatistics(points: points([(0, -1), (0, 1)]))
        let separation = ClusterStatistics.separation(a, b, minStd: 0.5)
        #expect(separation.meanDistance == 0)
        #expect(separation.dPrime == 0)
    }

    @Test func dPrimeIsSymmetric() {
        let a = ClusterStatistics(points: points([(0, 0), (1, 2), (2, 1), (3, 3)]))
        let b = ClusterStatistics(points: points([(8, 1), (9, 3), (10, 2)]))
        let forward = ClusterStatistics.separation(a, b, minStd: 0.5)
        let backward = ClusterStatistics.separation(b, a, minStd: 0.5)
        #expect(abs(forward.dPrime - backward.dPrime) < 1e-12)
        #expect(abs(forward.meanDistance - backward.meanDistance) < 1e-12)
    }
}
