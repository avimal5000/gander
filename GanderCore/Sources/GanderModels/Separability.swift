import Foundation

/// Which 2-D pose features the gate analysis evaluates.
public enum PoseFeatureSet: String, Sendable, Codable, CaseIterable {
    /// (`yaw`, `pitch`) from Vision.
    case visionAngles
    /// (`landmarkYaw`, `landmarkPitch`) from landmark geometry.
    case landmarkAngles
}

/// Per-display statistics for one feature set. `x` is the yaw-like axis, `y` the pitch-like axis.
public struct DisplayPoseStats: Sendable, Equatable, Codable {
    public var displayID: DisplayID
    public var displayName: String
    /// All frames in this display's labeled segments.
    public var frameCount: Int
    /// Frames with a face and this feature set available.
    public var faceCount: Int
    public var meanX: Double
    public var meanY: Double
    /// Sample standard deviations (n - 1), degrees.
    public var stdX: Double
    public var stdY: Double

    /// `faceCount / frameCount`, 0 when there are no frames.
    public var faceDetectionRate: Double { frameCount == 0 ? 0 : Double(faceCount) / Double(frameCount) }

    public init(
        displayID: DisplayID,
        displayName: String,
        frameCount: Int,
        faceCount: Int,
        meanX: Double,
        meanY: Double,
        stdX: Double,
        stdY: Double
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.frameCount = frameCount
        self.faceCount = faceCount
        self.meanX = meanX
        self.meanY = meanY
        self.stdX = stdX
        self.stdY = stdY
    }
}

/// How well two displays' pose clusters separate.
public struct PairSeparation: Sendable, Equatable, Codable {
    public var first: DisplayID
    public var second: DisplayID
    /// Euclidean distance between the two cluster means, degrees.
    public var meanDistance: Double
    /// Fisher separation along the line joining the means (definition in CONTRACT.md).
    public var dPrime: Double

    public init(first: DisplayID, second: DisplayID, meanDistance: Double, dPrime: Double) {
        self.first = first
        self.second = second
        self.meanDistance = meanDistance
        self.dPrime = dPrime
    }
}

public enum GateVerdict: String, Sendable, Codable, Comparable {
    case insufficientData
    case noGo
    case marginal
    case go

    private var rank: Int {
        switch self {
        case .insufficientData: 0
        case .noGo: 1
        case .marginal: 2
        case .go: 3
        }
    }

    public static func < (lhs: GateVerdict, rhs: GateVerdict) -> Bool { lhs.rank < rhs.rank }
}

/// Thresholds for the M1 go/no-go verdict.
public struct GateThresholds: Sendable, Equatable, Codable {
    public var minFaceSamplesPerDisplay: Int
    public var goDPrime: Double
    public var goAccuracy: Double
    public var goFaceDetectionRate: Double
    public var marginalDPrime: Double
    public var marginalAccuracy: Double
    public var marginalFaceDetectionRate: Double
    /// Standard deviations are floored at this many degrees in d' and classification.
    public var minStd: Double

    public init(
        minFaceSamplesPerDisplay: Int = 30,
        goDPrime: Double = 3.0,
        goAccuracy: Double = 0.95,
        goFaceDetectionRate: Double = 0.9,
        marginalDPrime: Double = 2.0,
        marginalAccuracy: Double = 0.85,
        marginalFaceDetectionRate: Double = 0.75,
        minStd: Double = 0.5
    ) {
        self.minFaceSamplesPerDisplay = minFaceSamplesPerDisplay
        self.goDPrime = goDPrime
        self.goAccuracy = goAccuracy
        self.goFaceDetectionRate = goFaceDetectionRate
        self.marginalDPrime = marginalDPrime
        self.marginalAccuracy = marginalAccuracy
        self.marginalFaceDetectionRate = marginalFaceDetectionRate
        self.minStd = minStd
    }

    public static let `default` = GateThresholds()
}

/// Separability results for one feature set.
public struct SeparabilityReport: Sendable, Equatable, Codable {
    public var featureSet: PoseFeatureSet
    /// One entry per labeled display, in the order displays first appear in the trace.
    public var displays: [DisplayPoseStats]
    /// Every unordered pair of labeled displays.
    public var pairs: [PairSeparation]
    /// Held-out nearest-centroid accuracy, 0...1; `nil` when data is insufficient.
    public var accuracy: Double?
    public var verdict: GateVerdict
    /// Human-readable observations (for example "Landmarks unavailable in 40% of frames").
    public var notes: [String]

    public init(
        featureSet: PoseFeatureSet,
        displays: [DisplayPoseStats],
        pairs: [PairSeparation],
        accuracy: Double?,
        verdict: GateVerdict,
        notes: [String]
    ) {
        self.featureSet = featureSet
        self.displays = displays
        self.pairs = pairs
        self.accuracy = accuracy
        self.verdict = verdict
        self.notes = notes
    }
}

/// Full gate analysis: one report per feature set plus the overall verdict.
public struct GateAnalysis: Sendable, Equatable, Codable {
    /// One report per `PoseFeatureSet.allCases`, in that order.
    public var reports: [SeparabilityReport]
    /// Best verdict across reports.
    public var overall: GateVerdict
    /// Feature set with the best verdict (ties: higher accuracy, then `allCases` order). `nil` if no reports.
    public var bestFeatureSet: PoseFeatureSet?
    public var thresholds: GateThresholds

    public init(
        reports: [SeparabilityReport], overall: GateVerdict, bestFeatureSet: PoseFeatureSet?, thresholds: GateThresholds
    ) {
        self.reports = reports
        self.overall = overall
        self.bestFeatureSet = bestFeatureSet
        self.thresholds = thresholds
    }

    public func report(for featureSet: PoseFeatureSet) -> SeparabilityReport? {
        reports.first { $0.featureSet == featureSet }
    }
}

/// Result of classifying one pose against a report's display clusters.
public struct DisplayClassification: Sendable, Equatable {
    public var displayID: DisplayID
    /// Normalized distance to the winning cluster (definition in CONTRACT.md).
    public var distance: Double
    /// Normalized distance to the second-nearest cluster; `nil` with one cluster.
    public var runnerUpDistance: Double?

    public init(displayID: DisplayID, distance: Double, runnerUpDistance: Double?) {
        self.displayID = displayID
        self.distance = distance
        self.runnerUpDistance = runnerUpDistance
    }
}

/// Computes the M1 separability analysis. Implemented by `PoseTraces.SeparabilityAnalyzer`.
public protocol SeparabilityAnalyzing: Sendable {
    /// Analyzes the labeled segments of `trace` (unlabeled segments are ignored).
    func analyze(_ trace: PoseTrace, thresholds: GateThresholds) -> GateAnalysis
    /// Nearest display cluster for `pose` under `report`'s feature set; `nil` if the pose lacks those
    /// features or the report has no displays.
    func classify(_ pose: HeadPose, using report: SeparabilityReport) -> DisplayClassification?
    /// Markdown suitable for `docs/decisions/` (date, camera, layout, thresholds, tables, verdict).
    func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String
}
