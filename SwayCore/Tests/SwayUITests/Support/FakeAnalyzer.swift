import Foundation
import SwayModels
import os

/// An analyzer that returns canned results and records what it was asked.
final class FakeAnalyzer: SeparabilityAnalyzing {
    struct State: Sendable {
        var analysis: GateAnalysis
        var classification: DisplayClassification?
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
            return $0.classification
        }
    }

    func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String {
        state.withLock { $0.markdown }
    }
}
