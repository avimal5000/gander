import GanderModels

/// Held-out nearest-centroid accuracy (CONTRACT.md 6.3, step 5).
enum HeldOutAccuracy {
    /// Points to fit centroids on and points to classify, per display (indexed like `displays`).
    private struct Fold {
        var train: [[FeaturePoint]]
        var test: [[FeaturePoint]]
    }

    /// `correct / total` over all held-out points, or `nil` when there are no test points.
    ///
    /// - With at least 2 distinct rounds among the labeled segments: leave-one-round-out. For each round, centroids
    ///   and stds come from the other rounds and the points of that round are classified.
    /// - With a single round: each segment's points (time order) are split; the first ⌊n/2⌋ train, the rest test.
    /// - A display with no training points in a fold is not a candidate, and its test points count as wrong.
    static func evaluate(displays: [LabeledDisplay], featureSet: PoseFeatureSet, minStd: Double) -> Double? {
        let rounds = Set(displays.flatMap { $0.segments.map(\.round) })
        let folds: [Fold]
        if rounds.count >= 2 {
            folds = rounds.sorted().map { leaveOneRoundOut($0, displays: displays, featureSet: featureSet) }
        } else {
            folds = [timeSplit(displays: displays, featureSet: featureSet)]
        }

        let classifier = NearestCentroidClassifier(minStd: minStd)
        var correct = 0
        var total = 0
        for fold in folds {
            let candidates = fold.train.enumerated().compactMap {
                index, points -> NearestCentroidClassifier.Candidate? in
                guard !points.isEmpty else { return nil }
                let statistics = ClusterStatistics(points: points)
                return NearestCentroidClassifier.Candidate(
                    index: index,
                    meanX: statistics.meanX,
                    meanY: statistics.meanY,
                    stdX: statistics.stdX,
                    stdY: statistics.stdY
                )
            }
            for (index, points) in fold.test.enumerated() {
                for point in points {
                    total += 1
                    if classifier.classify(point, among: candidates)?.index == index { correct += 1 }
                }
            }
        }
        return total > 0 ? Double(correct) / Double(total) : nil
    }

    private static func leaveOneRoundOut(
        _ round: Int,
        displays: [LabeledDisplay],
        featureSet: PoseFeatureSet
    ) -> Fold {
        func points(_ display: LabeledDisplay, where include: (LabeledSegment) -> Bool) -> [FeaturePoint] {
            display.segments.filter(include).flatMap { $0.points(for: featureSet) }
        }
        return Fold(
            train: displays.map { display in points(display) { $0.round != round } },
            test: displays.map { display in points(display) { $0.round == round } }
        )
    }

    private static func timeSplit(displays: [LabeledDisplay], featureSet: PoseFeatureSet) -> Fold {
        var train: [[FeaturePoint]] = []
        var test: [[FeaturePoint]] = []
        for display in displays {
            var displayTrain: [FeaturePoint] = []
            var displayTest: [FeaturePoint] = []
            for segment in display.segments {
                let points = segment.points(for: featureSet)
                let trainCount = points.count / 2
                displayTrain += points[..<trainCount]
                displayTest += points[trainCount...]
            }
            train.append(displayTrain)
            test.append(displayTest)
        }
        return Fold(train: train, test: test)
    }
}
