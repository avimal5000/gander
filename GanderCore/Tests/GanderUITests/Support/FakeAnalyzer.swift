import Foundation
import GanderModels
import os

/// An analyzer that returns canned results and records what it was asked.
final class FakeAnalyzer: SeparabilityAnalyzing {
    struct State: Sendable {
        var analysis: GateAnalysis
        var classification: DisplayClassification?
        /// Feature sets whose reports classify to `nil`, as when the pose lacks that set's features.
        var unclassifiable: Set<PoseFeatureSet> = []
        var markdown = "FAKE MARKDOWN"
        var analyzedTraces: [PoseTrace] = []
        var analyzedThresholds: [GateThresholds] = []
        var classifiedReports: [SeparabilityReport] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(analysis: GateAnalysis, classification: DisplayClassification? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(analysis: analysis, classification: classification))
    }

    var analyzedTraces: [PoseTrace] { state.withLock { $0.analyzedTraces } }
    var analyzedThresholds: [GateThresholds] { state.withLock { $0.analyzedThresholds } }
    var classifiedReports: [SeparabilityReport] { state.withLock { $0.classifiedReports } }

    func setClassification(_ value: DisplayClassification?) {
        state.withLock { $0.classification = value }
    }

    /// Makes `classify` return `nil` for reports of `featureSet`.
    func setUnclassifiable(_ featureSet: PoseFeatureSet, _ value: Bool = true) {
        state.withLock {
            if value { $0.unclassifiable.insert(featureSet) } else { $0.unclassifiable.remove(featureSet) }
        }
    }

    func analyze(_ trace: PoseTrace, thresholds: GateThresholds) -> GateAnalysis {
        state.withLock {
            $0.analyzedTraces.append(trace)
            $0.analyzedThresholds.append(thresholds)
            return $0.analysis
        }
    }

    func classify(_ pose: HeadPose, using report: SeparabilityReport) -> DisplayClassification? {
        state.withLock {
            $0.classifiedReports.append(report)
            return $0.unclassifiable.contains(report.featureSet) ? nil : $0.classification
        }
    }

    func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String {
        state.withLock { $0.markdown }
    }
}
