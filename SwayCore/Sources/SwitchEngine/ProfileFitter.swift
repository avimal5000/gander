import Foundation
import SwayModels
import os

/// Fits a `CalibrationProfile` from a labeled trace (CONTRACT section 6.6, "Fitting").
///
/// Pure and deterministic: the same trace, features, and rounds always give an equal profile, because
/// `createdAt` comes from the trace and every pass over the data runs in a fixed order.
struct ProfileFitter: Sendable {
    /// Lowest `yawScale`, degrees. Keeps a very still calibration from making every small wobble look large.
    static let yawScaleFloor = 1.5
    /// Lowest `pitchScale`, degrees.
    static let pitchScaleFloor = 2.5

    /// A display needs at least this many face samples (with the requested features) to be profiled.
    let minPointsPerDisplay: Int

    init(minPointsPerDisplay: Int = GateThresholds.default.minFaceSamplesPerDisplay) {
        self.minPointsPerDisplay = minPointsPerDisplay
    }

    /// Fits a profile.
    ///
    /// - Parameters:
    ///   - trace: Source of labeled segments; unlabeled segments (`displayID == nil`) are ignored.
    ///   - features: Which pose features to use.
    ///   - rounds: Only segments of these rounds; `nil` uses every round.
    /// - Throws: `CalibrationError.featuresMissing` when the used segments have face samples but none with the
    ///   features, and `CalibrationError.tooFewDisplays` when fewer than two displays reach `minPointsPerDisplay`
    ///   (including no face samples or no used segments at all).
    func fit(from trace: PoseTrace, features: PoseFeatureSet, rounds: Set<Int>?) throws -> CalibrationProfile {
        let collected = collectPoints(from: trace, features: features, rounds: rounds)

        // Step 3: faces without the features (landmarks in a live recording) is a different problem from too
        // little data. No faces or no labeled segments at all is too little data.
        guard collected.pointsByDisplay.values.contains(where: { !$0.isEmpty }) else {
            throw collected.faceSampleCount > 0
                ? CalibrationError.featuresMissing(features) : CalibrationError.tooFewDisplays
        }

        // Step 4: keep displays with enough points, in first-appearance order for now.
        let kept = collected.firstAppearance.filter {
            (collected.pointsByDisplay[$0]?.count ?? 0) >= minPointsPerDisplay
        }
        guard kept.count >= 2 else { throw CalibrationError.tooFewDisplays }

        // Steps 5 and 6: statistics per display, then the layout's left-to-right order.
        let profiles = orderedDisplays(kept, layout: trace.layout).compactMap { id -> DisplayProfile? in
            guard let points = collected.pointsByDisplay[id] else { return nil }
            return Self.displayProfile(id: id, points: points)
        }

        // Step 7: pooled within-display spread, floored; pitch never weighs more than yaw.
        let yawScale = max(Self.yawScaleFloor, Self.rootMeanSquare(profiles.map(\.yawStd)))
        let pitchScale = max(Self.pitchScaleFloor, yawScale, Self.rootMeanSquare(profiles.map(\.pitchStd)))

        // Step 8: bookkeeping fields.
        let profile = CalibrationProfile(
            features: features,
            displays: profiles,
            yawScale: yawScale,
            pitchScale: pitchScale,
            layoutFingerprint: trace.layout?.fingerprint ?? "",
            cameraName: trace.cameraName,
            createdAt: trace.createdAt
        )
        SwayLog.logger(category: "engine").debug(
            "fitted \(profiles.count) displays, yawScale \(yawScale), pitchScale \(pitchScale)"
        )
        return profile
    }

    // MARK: - Steps 1 and 2

    private struct CollectedPoints {
        /// Displays of the used segments, in order of first appearance.
        var firstAppearance: [DisplayID] = []
        var pointsByDisplay: [DisplayID: [FeaturePoint]] = [:]
        /// Samples of the used segments with a face, whether or not they have the requested features.
        var faceSampleCount = 0
    }

    /// Steps 1 and 2: the feature points of every labeled sample in the used segments, grouped by display.
    private func collectPoints(from trace: PoseTrace, features: PoseFeatureSet, rounds: Set<Int>?) -> CollectedPoints {
        var collected = CollectedPoints()
        for segment in trace.segments {
            guard let id = segment.displayID else { continue }
            if let rounds, !rounds.contains(segment.round) { continue }
            if collected.pointsByDisplay[id] == nil {
                collected.firstAppearance.append(id)
                collected.pointsByDisplay[id] = []
            }
            for sample in segment.samples {
                guard let pose = sample.pose else { continue }
                collected.faceSampleCount += 1
                guard let point = features.point(of: pose) else { continue }
                collected.pointsByDisplay[id, default: []].append(point)
            }
        }
        return collected
    }

    // MARK: - Step 6

    /// The layout's displays that were kept, in layout order, followed by kept displays the layout does not
    /// contain, in order of first appearance.
    private func orderedDisplays(_ kept: [DisplayID], layout: DisplayLayout?) -> [DisplayID] {
        let keptSet = Set(kept)
        var seen = Set<DisplayID>()
        var ordered: [DisplayID] = []
        for display in layout?.displays ?? [] where keptSet.contains(display.id) && seen.insert(display.id).inserted {
            ordered.append(display.id)
        }
        for id in kept where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }

    // MARK: - Step 5

    private static func displayProfile(id: DisplayID, points: [FeaturePoint]) -> DisplayProfile {
        let yaws = points.map(\.x)
        let pitches = points.map(\.y)
        let yawStats = meanAndStandardDeviation(of: yaws)
        let pitchStats = meanAndStandardDeviation(of: pitches)
        return DisplayProfile(
            displayID: id,
            yaw: yawStats.mean,
            pitch: pitchStats.mean,
            yawStd: yawStats.std,
            pitchStd: pitchStats.std,
            sampleCount: points.count
        )
    }

    /// Mean and sample standard deviation (n - 1; 0 when there are fewer than two values). Two passes, so the
    /// result stays accurate for angles that sit far from zero.
    private static func meanAndStandardDeviation(of values: [Double]) -> (mean: Double, std: Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count >= 2 else { return (mean, 0) }
        let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (mean, (squares / Double(values.count - 1)).squareRoot())
    }

    private static func rootMeanSquare(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
    }
}
