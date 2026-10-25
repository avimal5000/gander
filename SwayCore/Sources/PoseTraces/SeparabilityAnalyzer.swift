import Foundation
import SwayModels

/// Computes the M1 head-pose gate analysis from labeled trace segments (CONTRACT.md 6.3).
///
/// For each `PoseFeatureSet` it measures how well the displays' pose clusters separate (pairwise d′), how well a
/// nearest-centroid classifier recovers the display on held-out data, and the face detection rate, then derives a
/// verdict from the thresholds.
public struct SeparabilityAnalyzer: SeparabilityAnalyzing {
    /// Creates an analyzer. It is stateless.
    public init() {}

    /// Analyzes the labeled segments of `trace`; unlabeled segments are ignored.
    /// Reports are in `PoseFeatureSet.allCases` order and displays in order of first appearance.
    public func analyze(_ trace: PoseTrace, thresholds: GateThresholds) -> GateAnalysis {
        let displays = LabeledDisplay.group(trace)
        let reports = PoseFeatureSet.allCases.map { featureSet in
            Self.makeReport(featureSet: featureSet, displays: displays, thresholds: thresholds)
        }
        return GateAnalysis(
            reports: reports,
            overall: reports.map(\.verdict).max() ?? .insufficientData,
            bestFeatureSet: Self.bestFeatureSet(in: reports),
            thresholds: thresholds
        )
    }

    /// The display cluster of `report` nearest to `pose`, using `GateThresholds.default.minStd`.
    /// Returns `nil` when the pose lacks the report's features or the report has no displays.
    ///
    /// A display with no face samples (`faceCount == 0`) has no cluster, only placeholder statistics, so it is not a
    /// candidate, as in held-out accuracy (CONTRACT 6.3 step 5). Otherwise its zero mean would win for any pose near
    /// (0, 0), such as looking straight at the camera. With no candidates left the result is `nil`.
    public func classify(_ pose: HeadPose, using report: SeparabilityReport) -> DisplayClassification? {
        guard let point = report.featureSet.point(of: pose) else { return nil }
        let candidates = report.displays.enumerated().filter { $0.element.faceCount > 0 }.map { index, stats in
            NearestCentroidClassifier.Candidate(
                index: index,
                meanX: stats.meanX,
                meanY: stats.meanY,
                stdX: stats.stdX,
                stdY: stats.stdY
            )
        }
        let classifier = NearestCentroidClassifier(minStd: GateThresholds.default.minStd)
        guard let match = classifier.classify(point, among: candidates) else { return nil }
        return DisplayClassification(
            displayID: report.displays[match.index].displayID,
            distance: match.distance,
            runnerUpDistance: match.runnerUpDistance
        )
    }

    /// Markdown for `docs/decisions/`: date, camera, layout, verdict, thresholds, tables, accuracy and notes.
    public func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String {
        GateMarkdownFormatter.render(analysis: analysis, trace: trace)
    }

    // MARK: - Report construction

    private static func makeReport(
        featureSet: PoseFeatureSet,
        displays: [LabeledDisplay],
        thresholds: GateThresholds
    ) -> SeparabilityReport {
        let clouds = displays.map { ClusterStatistics(points: $0.points(for: featureSet)) }
        let stats = zip(displays, clouds).map { display, cloud in
            DisplayPoseStats(
                displayID: display.id,
                displayName: display.name,
                frameCount: display.frameCount,
                faceCount: cloud.count,
                meanX: cloud.meanX,
                meanY: cloud.meanY,
                stdX: cloud.stdX,
                stdY: cloud.stdY
            )
        }
        let pairs = pairs(stats: stats, clouds: clouds, minStd: thresholds.minStd)

        let isSufficient = stats.count >= 2 && stats.allSatisfy { $0.faceCount >= thresholds.minFaceSamplesPerDisplay }
        let accuracy =
            isSufficient
            ? HeldOutAccuracy.evaluate(displays: displays, featureSet: featureSet, minStd: thresholds.minStd)
            : nil
        let verdict =
            isSufficient
            ? verdict(stats: stats, pairs: pairs, accuracy: accuracy, thresholds: thresholds)
            : .insufficientData
        let notes = notes(
            featureSet: featureSet,
            displays: displays,
            stats: stats,
            pairs: pairs,
            isSufficient: isSufficient,
            thresholds: thresholds
        )

        return SeparabilityReport(
            featureSet: featureSet,
            displays: stats,
            pairs: pairs,
            accuracy: accuracy,
            verdict: verdict,
            notes: notes
        )
    }

    /// Every unordered pair (i < j) in display order, with its mean distance and d′ (CONTRACT.md 6.3, step 3).
    private static func pairs(
        stats: [DisplayPoseStats],
        clouds: [ClusterStatistics],
        minStd: Double
    ) -> [PairSeparation] {
        var pairs: [PairSeparation] = []
        for first in stats.indices {
            for second in stats.indices where second > first {
                let separation = ClusterStatistics.separation(clouds[first], clouds[second], minStd: minStd)
                pairs.append(
                    PairSeparation(
                        first: stats[first].displayID,
                        second: stats[second].displayID,
                        meanDistance: separation.meanDistance,
                        dPrime: separation.dPrime
                    )
                )
            }
        }
        return pairs
    }

    /// `go` when every pair, the accuracy and every display's face rate meet the go thresholds; `marginal` when
    /// they meet the marginal thresholds; otherwise `noGo`. A missing accuracy fails both.
    private static func verdict(
        stats: [DisplayPoseStats],
        pairs: [PairSeparation],
        accuracy: Double?,
        thresholds: GateThresholds
    ) -> GateVerdict {
        func meets(dPrime: Double, accuracy minimumAccuracy: Double, faceRate: Double) -> Bool {
            guard let accuracy else { return false }
            return pairs.allSatisfy { $0.dPrime >= dPrime }
                && accuracy >= minimumAccuracy
                && stats.allSatisfy { $0.faceDetectionRate >= faceRate }
        }
        if meets(dPrime: thresholds.goDPrime, accuracy: thresholds.goAccuracy, faceRate: thresholds.goFaceDetectionRate)
        {
            return .go
        }
        if meets(
            dPrime: thresholds.marginalDPrime,
            accuracy: thresholds.marginalAccuracy,
            faceRate: thresholds.marginalFaceDetectionRate
        ) {
            return .marginal
        }
        return .noGo
    }

    /// Plain-sentence observations: why data is insufficient (when it is), the weakest pair and its d′, displays
    /// below the face-rate thresholds, and for landmarks the share of face frames without landmarks.
    private static func notes(
        featureSet: PoseFeatureSet,
        displays: [LabeledDisplay],
        stats: [DisplayPoseStats],
        pairs: [PairSeparation],
        isSufficient: Bool,
        thresholds: GateThresholds
    ) -> [String] {
        var notes: [String] = []

        if !isSufficient {
            if stats.count < 2 {
                notes.append("Fewer than 2 labeled displays were recorded, so displays cannot be compared.")
            }
            for stat in stats where stat.faceCount < thresholds.minFaceSamplesPerDisplay {
                notes.append(
                    "\(stat.displayName) has only \(stat.faceCount) usable samples; "
                        + "at least \(thresholds.minFaceSamplesPerDisplay) are needed."
                )
            }
        }

        if let weakest = pairs.min(by: { $0.dPrime < $1.dPrime }) {
            let nameOf = { (id: DisplayID) in stats.first { $0.displayID == id }?.displayName ?? id.rawValue }
            notes.append(
                "Weakest pair: \(nameOf(weakest.first)) and \(nameOf(weakest.second)), d′ \(weakest.dPrime.oneDecimal)."
            )
        }

        for stat in stats {
            let rate = stat.faceDetectionRate
            if rate < thresholds.marginalFaceDetectionRate {
                notes.append(
                    "\(stat.displayName): face detected in only \(rate.percentOneDecimal)% of frames, below the "
                        + "\(thresholds.marginalFaceDetectionRate.percentOneDecimal)% needed for MARGINAL."
                )
            } else if rate < thresholds.goFaceDetectionRate {
                notes.append(
                    "\(stat.displayName): face detected in only \(rate.percentOneDecimal)% of frames, below the "
                        + "\(thresholds.goFaceDetectionRate.percentOneDecimal)% needed for GO."
                )
            }
        }

        if featureSet == .landmarkAngles {
            let faceFrames = displays.reduce(0) { $0 + $1.faceFrameCount }
            if faceFrames > 0 {
                let withLandmarks = stats.reduce(0) { $0 + $1.faceCount }
                let missing = Double(faceFrames - withLandmarks) / Double(faceFrames)
                notes.append("Landmarks were unavailable in \(missing.percentOneDecimal)% of frames with a face.")
            }
        }
        return notes
    }

    // MARK: - Feature set choice

    /// The feature set with the best verdict. Ties go to the higher accuracy (`nil` counts as −1), then to
    /// `PoseFeatureSet.allCases` order. `nil` when there are no reports.
    static func bestFeatureSet(in reports: [SeparabilityReport]) -> PoseFeatureSet? {
        func rank(_ report: SeparabilityReport) -> Int {
            PoseFeatureSet.allCases.firstIndex(of: report.featureSet) ?? PoseFeatureSet.allCases.count
        }
        var best: SeparabilityReport?
        for report in reports {
            guard let current = best else {
                best = report
                continue
            }
            let candidate = (report.verdict, report.accuracy ?? -1, -rank(report))
            let incumbent = (current.verdict, current.accuracy ?? -1, -rank(current))
            if candidate > incumbent { best = report }
        }
        return best?.featureSet
    }
}
