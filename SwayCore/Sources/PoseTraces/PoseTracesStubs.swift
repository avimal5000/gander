import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The PoseTraces builder replaces this file. See CONTRACT.md.

/// JSON trace persistence.
public struct FileTraceStore: TraceStoring {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory =
            directory ?? URL.applicationSupportDirectory.appending(path: "Sway/Traces", directoryHint: .isDirectory)
    }

    public func save(_ trace: PoseTrace) throws -> URL { throw TraceStoreError.disabledInReleaseBuilds }

    public func load(_ url: URL) throws -> PoseTrace { throw TraceStoreError.io("stub") }

    public func list() throws -> [URL] { [] }
}

/// M1 gate separability analysis.
public struct SeparabilityAnalyzer: SeparabilityAnalyzing {
    public init() {}

    public func analyze(_ trace: PoseTrace, thresholds: GateThresholds) -> GateAnalysis {
        GateAnalysis(reports: [], overall: .insufficientData, bestFeatureSet: nil, thresholds: thresholds)
    }

    public func classify(_ pose: HeadPose, using report: SeparabilityReport) -> DisplayClassification? { nil }

    public func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String { "" }
}

/// Replays a recorded trace as a pose source.
public final class ReplayPoseSource: PoseSource {
    private let trace: PoseTrace
    private let speed: Double

    public init(trace: PoseTrace, speed: Double = 1.0) {
        self.trace = trace
        self.speed = speed
    }

    public func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        AsyncStream { $0.finish() }
    }

    public func stop() async {}
}

/// One synthetic pose cluster (a display the simulated user looks at).
public struct SyntheticCluster: Sendable, Equatable {
    public var displayID: DisplayID
    public var yaw: Double
    public var pitch: Double

    public init(displayID: DisplayID, yaw: Double, pitch: Double) {
        self.displayID = displayID
        self.yaw = yaw
        self.pitch = pitch
    }
}

/// Deterministic synthetic traces for tests and previews.
public enum SyntheticTraces {
    public static func gateTrace(
        clusters: [SyntheticCluster],
        std: Double,
        samplesPerSegment: Int,
        rounds: Int,
        faceDropRate: Double = 0,
        frameRate: Double = SwayPolicy.defaultFrameRate,
        seed: UInt64
    ) -> PoseTrace {
        PoseTrace()
    }
}
