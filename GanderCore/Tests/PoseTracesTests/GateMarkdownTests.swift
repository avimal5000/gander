import Foundation
import GanderModels
import Testing

@testable import PoseTraces

@Suite struct GateMarkdownTests {
    private let analyzer = SeparabilityAnalyzer()

    private func goTrace() -> PoseTrace {
        SyntheticTraces.gateTrace(
            clusters: leftRightClusters,
            std: 2,
            samplesPerSegment: 60,
            rounds: 2,
            seed: 1
        )
    }

    private func markdown(for trace: PoseTrace, thresholds: GateThresholds = .default) -> String {
        analyzer.markdownSummary(of: analyzer.analyze(trace, thresholds: thresholds), trace: trace)
    }

    @Test func containsHeadingVerdictAndBothFeatureSections() {
        let text = markdown(for: goTrace())
        #expect(text.hasPrefix("## M1 head-pose gate result\n"))
        #expect(text.contains("- Overall verdict: **GO** (best feature set: Vision angles)"))
        #expect(text.contains("### Vision angles — GO"))
        #expect(text.contains("### Landmark angles — GO"))
        #expect(text.hasSuffix("\n"))
    }

    @Test func containsDisplayTableAndPairTableForEachFeatureSet() {
        let text = markdown(for: goTrace())
        let displayHeader = "| Display | Frames | Face % | Mean yaw | Mean pitch | Std yaw | Std pitch |"
        let pairHeader = "| Pair | Mean distance | d′ |"
        #expect(text.components(separatedBy: displayHeader).count - 1 == 2)
        #expect(text.components(separatedBy: pairHeader).count - 1 == 2)
        #expect(text.contains("| Display 1 | 120 | 100.0 |"))
        #expect(text.contains("| Display 2 | 120 | 100.0 |"))
        #expect(text.contains("| Display 1 vs Display 2 | "))
        #expect(text.contains("Held-out accuracy: 100.0%"))
    }

    @Test func headerBulletsListDateCameraDisplaysAndThresholds() throws {
        var trace = goTrace()
        trace.layout = DisplayLayout(displays: [
            DisplayInfo(
                id: .left,
                cgDisplayID: 1,
                name: "Built-in Retina Display",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                isBuiltIn: true,
                isMain: true
            ),
            DisplayInfo(
                id: .right,
                cgDisplayID: 2,
                name: "LG UltraFine",
                frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                isBuiltIn: false,
                isMain: false
            ),
        ])
        trace.cameraName = "FaceTime HD Camera"
        let text = markdown(for: trace)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        #expect(text.contains("- Date: \(formatter.string(from: trace.createdAt))\n"))
        #expect(text.contains("- Camera: FaceTime HD Camera\n"))
        #expect(
            text.contains("- Displays: Built-in Retina Display (1512x982 pt, built-in), LG UltraFine (2560x1440 pt)\n"))
        #expect(
            text.contains(
                "- Thresholds: GO needs d′ ≥ 3.0, accuracy ≥ 95.0%, face detection ≥ 90.0%; "
                    + "MARGINAL needs d′ ≥ 2.0, accuracy ≥ 85.0%, face detection ≥ 75.0%; "
                    + "at least 30 face samples per display; standard deviations floored at 0.5°."
            )
        )
    }

    @Test func missingCameraAndLayoutAreDescribedAsUnknown() {
        var trace = goTrace()
        trace.cameraName = nil
        trace.layout = nil
        let text = markdown(for: trace)
        #expect(text.contains("- Camera: unknown\n"))
        #expect(text.contains("- Displays: unknown (no layout recorded)\n"))
    }

    @Test func verdictLabelsCoverEveryOutcome() {
        let noGoTrace = SyntheticTraces.gateTrace(
            clusters: [
                SyntheticCluster(displayID: .left, yaw: 0, pitch: 0),
                SyntheticCluster(displayID: .right, yaw: 1, pitch: 0),
            ],
            std: 3,
            samplesPerSegment: 60,
            rounds: 2,
            seed: 2
        )
        #expect(markdown(for: noGoTrace).contains("- Overall verdict: **NO-GO**"))
        #expect(markdown(for: noGoTrace).contains("### Vision angles — NO-GO"))

        let marginalTrace = SyntheticTraces.gateTrace(
            clusters: leftRightClusters,
            std: 2,
            samplesPerSegment: 60,
            rounds: 2,
            faceDropRate: 0.2,
            seed: 1
        )
        #expect(markdown(for: marginalTrace).contains("- Overall verdict: **MARGINAL**"))

        let sparse = markdown(for: PoseTrace())
        #expect(sparse.contains("- Overall verdict: **INSUFFICIENT DATA**"))
        #expect(sparse.contains("### Vision angles — INSUFFICIENT DATA"))
        #expect(sparse.contains("No labeled displays were recorded."))
        #expect(sparse.contains("Held-out accuracy: not available"))
    }

    @Test func numbersUseOneDecimalAndNotesAreListed() {
        let analysis = GateAnalysis(
            reports: [
                SeparabilityReport(
                    featureSet: .visionAngles,
                    displays: [
                        DisplayPoseStats(
                            displayID: .left,
                            displayName: "Left | main",
                            frameCount: 200,
                            faceCount: 183,
                            meanX: -12.345,
                            meanY: -0.04,
                            stdX: 1.25,
                            stdY: 0.849
                        ),
                        DisplayPoseStats(
                            displayID: .right,
                            displayName: "Right",
                            frameCount: 200,
                            faceCount: 200,
                            meanX: 12.351,
                            meanY: 3.96,
                            stdX: 2,
                            stdY: 1
                        ),
                    ],
                    pairs: [PairSeparation(first: .left, second: .right, meanDistance: 24.77, dPrime: 7.249)],
                    accuracy: 0.97543,
                    verdict: .marginal,
                    notes: ["First note.", "Second note."]
                )
            ],
            overall: .marginal,
            bestFeatureSet: .visionAngles,
            thresholds: .default
        )
        let text = analyzer.markdownSummary(of: analysis, trace: PoseTrace())
        #expect(text.contains("| Left \\| main | 200 | 91.5 | -12.3 | 0.0 | 1.2 | 0.8 |"))
        #expect(text.contains("| Right | 200 | 100.0 | 12.4 | 4.0 | 2.0 | 1.0 |"))
        #expect(text.contains("| Left \\| main vs Right | 24.8 | 7.2 |"))
        #expect(text.contains("Held-out accuracy: 97.5%"))
        #expect(text.contains("Notes:\n- First note.\n- Second note."))
    }

    @Test func reportWithNoNotesSaysSo() {
        let text = markdown(for: goTrace())
        #expect(text.contains("Notes:\n- Weakest pair: Display 1 and Display 2, d′ "))
        let bare = GateAnalysis(
            reports: [
                SeparabilityReport(
                    featureSet: .landmarkAngles,
                    displays: [],
                    pairs: [],
                    accuracy: nil,
                    verdict: .insufficientData,
                    notes: []
                )
            ],
            overall: .insufficientData,
            bestFeatureSet: nil,
            thresholds: .default
        )
        let bareText = analyzer.markdownSummary(of: bare, trace: PoseTrace())
        #expect(bareText.contains("Notes: none."))
        #expect(!bareText.contains("best feature set"))
        #expect(bareText.contains("No display pairs to compare."))
    }

    @Test func oneDecimalFormattingIsLocaleIndependentAndNeverNegativeZero() {
        #expect((-0.04).oneDecimal == "0.0")
        #expect(12.0.oneDecimal == "12.0")
        #expect((-3.26).oneDecimal == "-3.3")
        #expect(0.9753.percentOneDecimal == "97.5")
    }
}
