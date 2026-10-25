import Testing

@testable import PoseTraces

@Suite struct NearestCentroidClassifierTests {
    private let classifier = NearestCentroidClassifier(minStd: 0.5)

    private func candidate(
        _ index: Int,
        mean: (Double, Double),
        std: (Double, Double)
    ) -> NearestCentroidClassifier.Candidate {
        .init(index: index, meanX: mean.0, meanY: mean.1, stdX: std.0, stdY: std.1)
    }

    @Test func normalizedDistanceUsesPerAxisStd() {
        let cluster = candidate(0, mean: (0, 0), std: (2, 1))
        // z = sqrt((3/2)² + (1/1)²) = sqrt(3.25)
        let z = classifier.normalizedDistance(from: FeaturePoint(x: 3, y: 1), to: cluster)
        #expect(abs(z - 3.25.squareRoot()) < 1e-12)
    }

    @Test func tinyStdIsFlooredAtMinStd() {
        let cluster = candidate(0, mean: (0, 0), std: (0, 0.1))
        // Both axes floored to 0.5: z = sqrt((1/0.5)² + (1/0.5)²)
        let z = classifier.normalizedDistance(from: FeaturePoint(x: 1, y: 1), to: cluster)
        #expect(abs(z - 8.0.squareRoot()) < 1e-12)
    }

    @Test func nearestWinsAndRunnerUpIsSecondNearest() {
        let candidates = [
            candidate(0, mean: (0, 0), std: (1, 1)),
            candidate(1, mean: (10, 0), std: (1, 1)),
            candidate(2, mean: (20, 0), std: (1, 1)),
        ]
        let match = classifier.classify(FeaturePoint(x: 8, y: 0), among: candidates)
        #expect(match?.index == 1)
        #expect(match?.distance == 2)
        #expect(match?.runnerUpDistance == 8)
    }

    @Test func tiesGoToTheEarlierCandidate() {
        let candidates = [
            candidate(0, mean: (-5, 0), std: (1, 1)),
            candidate(1, mean: (5, 0), std: (1, 1)),
        ]
        let match = classifier.classify(FeaturePoint(x: 0, y: 0), among: candidates)
        #expect(match?.index == 0)
        #expect(match?.runnerUpDistance == match?.distance)
    }

    @Test func noCandidatesGiveNoMatchAndSingleCandidateHasNoRunnerUp() {
        #expect(classifier.classify(FeaturePoint(x: 0, y: 0), among: []) == nil)
        let single = classifier.classify(FeaturePoint(x: 1, y: 0), among: [candidate(4, mean: (0, 0), std: (1, 1))])
        #expect(single?.index == 4)
        #expect(single?.runnerUpDistance == nil)
    }
}
