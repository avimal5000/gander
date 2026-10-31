import Foundation
import GanderModels
import Testing

@testable import PoseTraces

@Suite struct SeparabilityAnalyzerTests {
    private let analyzer = SeparabilityAnalyzer()

    private func gate(
        clusters: [SyntheticCluster] = leftRightClusters,
        std: Double = 2,
        samples: Int = 60,
        rounds: Int = 2,
        drop: Double = 0,
        seed: UInt64 = 1
    ) -> PoseTrace {
        SyntheticTraces.gateTrace(
            clusters: clusters,
            std: std,
            samplesPerSegment: samples,
            rounds: rounds,
            faceDropRate: drop,
            seed: seed
        )
    }

    // MARK: - Verdicts

    @Test func wellSeparatedClustersAreGo() {
        let analysis = analyzer.analyze(gate(), thresholds: .default)
        #expect(analysis.overall == .go)
        for report in analysis.reports {
            #expect(report.verdict == .go)
            #expect(report.accuracy == 1)
            #expect(report.pairs.count == 1)
            #expect(report.pairs[0].dPrime > 3)
        }
        #expect(analysis.bestFeatureSet == .visionAngles)
        #expect(analysis.thresholds == .default)
    }

    @Test func threeWellSeparatedDisplaysYieldAllPairs() {
        let clusters = leftRightClusters + [SyntheticCluster(displayID: .top, yaw: 0, pitch: 25)]
        let analysis = analyzer.analyze(gate(clusters: clusters), thresholds: .default)
        #expect(analysis.overall == .go)
        let report = analysis.reports[0]
        #expect(report.displays.map(\.displayID) == [.left, .right, .top])
        #expect(report.pairs.map { [$0.first, $0.second] } == [[.left, .right], [.left, .top], [.right, .top]])
    }

    @Test func overlappingClustersAreNoGo() {
        let clusters = [
            SyntheticCluster(displayID: .left, yaw: 0, pitch: 0),
            SyntheticCluster(displayID: .right, yaw: 2, pitch: 0),
        ]
        let analysis = analyzer.analyze(gate(clusters: clusters, std: 3), thresholds: .default)
        #expect(analysis.overall == .noGo)
        for report in analysis.reports {
            #expect(report.verdict == .noGo)
            #expect(report.pairs[0].dPrime < 2)
            #expect(report.notes.contains { $0.hasPrefix("Weakest pair: Display 1 and Display 2, d′ ") })
        }
    }

    @Test func tooFewSamplesAreInsufficientData() {
        let analysis = analyzer.analyze(gate(samples: 10), thresholds: .default)  // 20 per display < 30
        #expect(analysis.overall == .insufficientData)
        for report in analysis.reports {
            #expect(report.verdict == .insufficientData)
            #expect(report.accuracy == nil)
            #expect(report.pairs.count == 1)  // statistics are still reported
            #expect(report.notes.contains { $0.contains("only 20 usable samples") })
        }
    }

    @Test func fewerThanTwoLabeledDisplaysAreInsufficientData() {
        let single = gate(clusters: [leftRightClusters[0]])
        let analysis = analyzer.analyze(single, thresholds: relaxedThresholds)
        #expect(analysis.overall == .insufficientData)
        #expect(analysis.reports[0].displays.count == 1)
        #expect(analysis.reports[0].pairs.isEmpty)
        #expect(analysis.reports[0].accuracy == nil)

        let empty = analyzer.analyze(PoseTrace(), thresholds: .default)
        #expect(empty.overall == .insufficientData)
        #expect(empty.reports.map(\.featureSet) == PoseFeatureSet.allCases)
        #expect(empty.reports.allSatisfy { $0.displays.isEmpty && $0.pairs.isEmpty })
        #expect(empty.bestFeatureSet == .visionAngles)
    }

    @Test func moderateFaceDropLowersVerdictToMarginal() {
        // 20% of frames without a face: face rate 0.8 is between the marginal (0.75) and go (0.9) thresholds.
        let analysis = analyzer.analyze(gate(drop: 0.2), thresholds: .default)
        for report in analysis.reports {
            #expect(report.verdict == .marginal)
            #expect(report.accuracy == 1)
            #expect(report.pairs.allSatisfy { $0.dPrime >= 3 })
            #expect(report.displays.allSatisfy { abs($0.faceDetectionRate - 0.8) < 1e-12 })
            #expect(report.notes.contains { $0.contains("80.0% of frames") && $0.contains("90.0% needed for GO") })
        }
        #expect(analysis.overall == .marginal)
    }

    @Test func heavyFaceDropIsNoGo() {
        let analysis = analyzer.analyze(gate(drop: 0.4), thresholds: .default)
        #expect(analysis.overall == .noGo)
        for report in analysis.reports {
            #expect(report.verdict == .noGo)
            #expect(
                report.notes.contains { $0.contains("60.0% of frames") && $0.contains("75.0% needed for MARGINAL") })
        }
    }

    @Test func verdictThresholdsAreInclusive() {
        // Exactly on the go thresholds still passes.
        let thresholds = GateThresholds(
            minFaceSamplesPerDisplay: 1,
            goDPrime: 0,
            goAccuracy: 1,
            goFaceDetectionRate: 0.8,
            marginalDPrime: 0,
            marginalAccuracy: 0,
            marginalFaceDetectionRate: 0
        )
        let analysis = analyzer.analyze(gate(drop: 0.2), thresholds: thresholds)
        #expect(analysis.reports[0].verdict == .go)
    }

    @Test func missingLandmarksAffectOnlyTheLandmarkReport() {
        var trace = gate()
        for segmentIndex in trace.segments.indices {
            for sampleIndex in trace.segments[segmentIndex].samples.indices {
                // Drop the landmark proxy from every second frame.
                if sampleIndex % 2 == 0 {
                    trace.segments[segmentIndex].samples[sampleIndex].pose?.landmarkYaw = nil
                    trace.segments[segmentIndex].samples[sampleIndex].pose?.landmarkPitch = nil
                }
            }
        }
        let analysis = analyzer.analyze(trace, thresholds: .default)
        let vision = analysis.reports[0]
        let landmarks = analysis.reports[1]
        #expect(vision.verdict == .go)
        #expect(vision.displays.allSatisfy { $0.faceCount == 120 })
        #expect(landmarks.displays.allSatisfy { $0.faceCount == 60 && $0.frameCount == 120 })
        #expect(landmarks.verdict == .noGo)  // face rate 0.5 < 0.75
        #expect(landmarks.notes.contains("Landmarks were unavailable in 50.0% of frames with a face."))
        #expect(!vision.notes.contains { $0.contains("Landmarks") })
        #expect(analysis.overall == .go)
        #expect(analysis.bestFeatureSet == .visionAngles)
    }

    // MARK: - Labeled data handling

    @Test func displaysFollowFirstAppearanceAndNamesComeFromTheLayout() {
        var trace = gate()
        trace.segments.reverse()  // right appears first
        let analysis = analyzer.analyze(trace, thresholds: .default)
        #expect(analysis.reports[0].displays.map(\.displayID) == [.right, .left])
        #expect(analysis.reports[0].displays.map(\.displayName) == ["Display 2", "Display 1"])
        #expect(analysis.reports[0].pairs.map { [$0.first, $0.second] } == [[.right, .left]])
    }

    @Test func displayNameFallsBackToRawIDWithoutLayout() {
        var trace = gate()
        trace.layout = nil
        let analysis = analyzer.analyze(trace, thresholds: .default)
        #expect(analysis.reports[0].displays.map(\.displayName) == ["left", "right"])
    }

    @Test func unlabeledSegmentsAreIgnored() {
        var trace = gate()
        trace.segments.append(makeSegment(nil, round: 0, points: Array(repeating: (100, 100), count: 500)))
        let analysis = analyzer.analyze(trace, thresholds: .default)
        #expect(analysis.reports[0].displays.count == 2)
        #expect(analysis.reports[0].displays.allSatisfy { $0.frameCount == 120 })
        #expect(analysis.overall == .go)
    }

    @Test func statsAreMeansAndSampleStdOfFacePoints() {
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(0, 0), (2, 4)]),
                makeSegment(.right, round: 1, points: [(10, 10), (14, 10)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        let left = report.displays[0]
        #expect(left.frameCount == 2)
        #expect(left.faceCount == 2)
        #expect(left.meanX == 1)
        #expect(left.meanY == 2)
        #expect(abs(left.stdX - 2.0.squareRoot()) < 1e-12)  // sqrt(((-1)² + 1²) / 1)
        #expect(abs(left.stdY - 8.0.squareRoot()) < 1e-12)
        #expect(report.displays[1].stdY == 0)
        #expect(report.pairs[0].meanDistance > 0)
    }

    @Test func dPrimeInReportMatchesHandComputedCase() {
        let a: [(Double, Double)] = [(0, 0), (1, 1), (2, 2)]
        let b: [(Double, Double)] = [(3, 4), (4, 5), (5, 6)]
        let trace = PoseTrace(segments: [
            makeSegment(.left, round: 1, points: a), makeSegment(.right, round: 1, points: b),
        ])
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        #expect(abs(report.pairs[0].meanDistance - 5) < 1e-12)
        #expect(abs(report.pairs[0].dPrime - 5.0 / 1.4) < 1e-12)
    }

    // MARK: - Accuracy

    @Test func multiRoundAccuracyIsLeaveOneRoundOut() {
        // Round 2 contains one left sample at x = 9 that sits on the right cluster: 12 of 13 held-out points
        // are classified correctly. Folds: hold out round 1 (train on round 2), then hold out round 2.
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(-1, 0), (0, 0), (1, 0)]),
                makeSegment(.right, round: 1, points: [(9, 0), (10, 0), (11, 0)]),
                makeSegment(.left, round: 2, points: [(-1, 0), (0, 0), (1, 0), (9, 0)]),
                makeSegment(.right, round: 2, points: [(9, 0), (10, 0), (11, 0)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        let accuracy = report.accuracy
        #expect(accuracy != nil)
        #expect(abs((accuracy ?? 0) - 12.0 / 13.0) < 1e-12)
    }

    @Test func singleRoundAccuracySplitsEachSegmentInTimeOrder() {
        // Six points per display: the first three train, the last three test. The stray left sample at x = 9 is
        // in the test half and falls on the right cluster.
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(-1, 0), (0, 0), (1, 0), (0, 0), (1, 0), (9, 0)]),
                makeSegment(.right, round: 1, points: [(9, 0), (10, 0), (11, 0), (9, 0), (10, 0), (11, 0)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        // Test points: left {0, 1, 9} (9 is wrong), right {9, 10, 11} -> 5 / 6.
        #expect(abs((report.accuracy ?? 0) - 5.0 / 6.0) < 1e-12)
    }

    @Test func singleRoundSplitUsesFloorHalfAsTrainingSize() {
        // Five points: floor(5 / 2) = 2 train, 3 test. The wrong point (index 2) must land in the test half,
        // giving 5 / 6; a ceiling split would train on it and test only two points per display.
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(0, 0), (0, 0), (9, 0), (0, 0), (0, 0)]),
                makeSegment(.right, round: 1, points: [(10, 0), (10, 0), (10, 0), (10, 0), (10, 0)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        #expect(abs((report.accuracy ?? 0) - 5.0 / 6.0) < 1e-12)
    }

    @Test func displayWithoutTrainingPointsInAFoldCountsAsWrong() {
        // The right display only appears in round 2.
        // - Hold out round 1: train on round 2 (left and right candidates); the 3 left test points are correct.
        // - Hold out round 2: train on round 1 (left only, right is not a candidate); the 3 left test points
        //   are correct and the 3 right test points count as wrong.
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(0, 0), (0, 0), (0, 0)]),
                makeSegment(.left, round: 2, points: [(0, 0), (0, 0), (0, 0)]),
                makeSegment(.right, round: 2, points: [(10, 0), (10, 0), (10, 0)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        #expect(abs((report.accuracy ?? 0) - 6.0 / 9.0) < 1e-12)
    }

    @Test func singlePointSegmentsHaveNoTrainingCandidatesSoTestPointsAreWrong() {
        // floor(1 / 2) = 0 training points per display, so there is no candidate and both test points are wrong.
        let trace = PoseTrace(
            segments: [
                makeSegment(.left, round: 1, points: [(0, 0)]),
                makeSegment(.right, round: 1, points: [(10, 0)]),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: relaxedThresholds).reports[0]
        #expect(report.accuracy == 0)
        #expect(report.verdict == .noGo)
    }

    @Test func accuracyIsNilWhenThereAreNoTestPoints() {
        // Sufficient by the thresholds (no samples required) but nothing to classify: no accuracy, so no go.
        let trace = PoseTrace(
            segments: [
                TraceSegment(displayID: .left, round: 1, samples: []),
                TraceSegment(displayID: .right, round: 1, samples: []),
            ]
        )
        let report = analyzer.analyze(trace, thresholds: GateThresholds(minFaceSamplesPerDisplay: 0)).reports[0]
        #expect(report.accuracy == nil)
        #expect(report.verdict == .noGo)
    }

    // MARK: - classify

    @Test func classifyPicksTheNearestClusterAndReportsRunnerUp() {
        let analysis = analyzer.analyze(gate(), thresholds: .default)
        for report in analysis.reports {
            let nearLeft = analyzer.classify(
                makePose(yaw: -19, pitch: 1, landmarkYaw: -17, landmarkPitch: 1), using: report)
            #expect(nearLeft?.displayID == .left)
            #expect((nearLeft?.runnerUpDistance ?? 0) > (nearLeft?.distance ?? .infinity))

            let nearRight = analyzer.classify(
                makePose(yaw: 22, pitch: -1, landmarkYaw: 20, landmarkPitch: -1), using: report)
            #expect(nearRight?.displayID == .right)
        }
    }

    @Test func classifyMatchesHandComputedDistances() {
        let report = SeparabilityReport(
            featureSet: .visionAngles,
            displays: [
                DisplayPoseStats(
                    displayID: .left,
                    displayName: "L",
                    frameCount: 10,
                    faceCount: 10,
                    meanX: 0,
                    meanY: 0,
                    stdX: 2,
                    stdY: 1
                ),
                DisplayPoseStats(
                    displayID: .right,
                    displayName: "R",
                    frameCount: 10,
                    faceCount: 10,
                    meanX: 10,
                    meanY: 0,
                    stdX: 2,
                    stdY: 0.1  // floored to 0.5
                ),
            ],
            pairs: [],
            accuracy: nil,
            verdict: .go,
            notes: []
        )
        let result = analyzer.classify(makePose(yaw: 3, pitch: 1), using: report)
        #expect(result?.displayID == .left)
        // z_left = sqrt((3/2)² + 1²); z_right = sqrt((-7/2)² + (1/0.5)²)
        #expect(abs((result?.distance ?? 0) - 3.25.squareRoot()) < 1e-12)
        #expect(abs((result?.runnerUpDistance ?? 0) - (12.25 + 4).squareRoot()) < 1e-12)
    }

    @Test func classifyReturnsNilWhenFeaturesOrDisplaysAreMissing() {
        let analysis = analyzer.analyze(gate(), thresholds: .default)
        let landmarkReport = analysis.reports[1]
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0), using: landmarkReport) == nil)
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0, landmarkYaw: 1), using: landmarkReport) == nil)
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0), using: analysis.reports[0]) != nil)

        var empty = analysis.reports[0]
        empty.displays = []
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0), using: empty) == nil)
    }

    @Test func classifyWithSingleDisplayHasNoRunnerUp() {
        var report = analyzer.analyze(gate(), thresholds: .default).reports[0]
        report.displays = [report.displays[0]]
        let result = analyzer.classify(makePose(yaw: -20, pitch: 0), using: report)
        #expect(result?.displayID == .left)
        #expect(result?.runnerUpDistance == nil)
    }

    @Test func classifyIgnoresADisplayWithoutFaceSamples() {
        // The right display never had a face in view, so its stats are placeholders (mean 0, std 0). A pose looking
        // straight at the camera must not be matched to that phantom cluster.
        var trace = gate()
        for index in trace.segments.indices where trace.segments[index].displayID == .right {
            for sample in trace.segments[index].samples.indices { trace.segments[index].samples[sample].pose = nil }
        }
        let report = analyzer.analyze(trace, thresholds: .default).reports[0]
        #expect(report.displays.map(\.faceCount) == [120, 0])
        #expect(report.verdict == .insufficientData)

        let result = analyzer.classify(makePose(yaw: 0, pitch: 0), using: report)
        #expect(result?.displayID == .left)
        #expect(result?.runnerUpDistance == nil)

        var noFaces = report
        noFaces.displays = noFaces.displays.map { stats in
            var empty = stats
            empty.faceCount = 0
            return empty
        }
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0), using: noFaces) == nil)
    }

    @Test func classifyTiesGoToTheEarlierDisplay() {
        let stats = { (id: DisplayID, x: Double) in
            DisplayPoseStats(
                displayID: id,
                displayName: id.rawValue,
                frameCount: 10,
                faceCount: 10,
                meanX: x,
                meanY: 0,
                stdX: 1,
                stdY: 1
            )
        }
        let report = SeparabilityReport(
            featureSet: .visionAngles,
            displays: [stats(.right, 5), stats(.left, -5)],
            pairs: [],
            accuracy: nil,
            verdict: .go,
            notes: []
        )
        #expect(analyzer.classify(makePose(yaw: 0, pitch: 0), using: report)?.displayID == .right)
    }

    // MARK: - Overall and best feature set

    private func report(_ featureSet: PoseFeatureSet, _ verdict: GateVerdict, accuracy: Double?) -> SeparabilityReport {
        SeparabilityReport(
            featureSet: featureSet,
            displays: [],
            pairs: [],
            accuracy: accuracy,
            verdict: verdict,
            notes: []
        )
    }

    @Test func bestFeatureSetPrefersTheBetterVerdictOverAccuracy() {
        let reports = [
            report(.visionAngles, .marginal, accuracy: 0.99),
            report(.landmarkAngles, .go, accuracy: 0.96),
        ]
        #expect(SeparabilityAnalyzer.bestFeatureSet(in: reports) == .landmarkAngles)
    }

    @Test func bestFeatureSetBreaksVerdictTiesByAccuracy() {
        let reports = [
            report(.visionAngles, .go, accuracy: 0.96),
            report(.landmarkAngles, .go, accuracy: 0.99),
        ]
        #expect(SeparabilityAnalyzer.bestFeatureSet(in: reports) == .landmarkAngles)
    }

    @Test func bestFeatureSetTreatsNilAccuracyAsMinusOne() {
        let reports = [
            report(.visionAngles, .insufficientData, accuracy: nil),
            report(.landmarkAngles, .insufficientData, accuracy: 0),
        ]
        #expect(SeparabilityAnalyzer.bestFeatureSet(in: reports) == .landmarkAngles)
    }

    @Test func bestFeatureSetFallsBackToAllCasesOrder() {
        let tied = [
            report(.landmarkAngles, .go, accuracy: 0.97),
            report(.visionAngles, .go, accuracy: 0.97),
        ]
        #expect(SeparabilityAnalyzer.bestFeatureSet(in: tied) == .visionAngles)
        #expect(SeparabilityAnalyzer.bestFeatureSet(in: []) == nil)
    }

    @Test func overallIsTheMaximumVerdictAcrossReports() {
        // Landmarks lack on every frame, so only the vision report can reach go.
        var trace = gate()
        for segmentIndex in trace.segments.indices {
            for sampleIndex in trace.segments[segmentIndex].samples.indices {
                trace.segments[segmentIndex].samples[sampleIndex].pose?.landmarkYaw = nil
                trace.segments[segmentIndex].samples[sampleIndex].pose?.landmarkPitch = nil
            }
        }
        let analysis = analyzer.analyze(trace, thresholds: .default)
        #expect(analysis.reports[0].verdict == .go)
        #expect(analysis.reports[1].verdict == .insufficientData)
        #expect(analysis.overall == .go)
        #expect(analysis.bestFeatureSet == .visionAngles)
        #expect(analysis.reports[1].notes.contains("Landmarks were unavailable in 100.0% of frames with a face."))
    }
}
