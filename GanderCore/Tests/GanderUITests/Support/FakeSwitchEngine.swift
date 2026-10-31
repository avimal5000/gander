import Foundation
import GanderModels
import os

/// The decisions a fake decider returns. Shared by the engine and every decider it makes, so a test can change the
/// script after a decider exists.
final class DecisionScript: Sendable {
    typealias Rule = @Sendable (PoseSample, SwitchContext) -> SwitchDecision

    private let rule: OSAllocatedUnfairLock<Rule>

    init() {
        rule = OSAllocatedUnfairLock(initialState: { _, _ in Fixtures.decision() })
    }

    func set(_ newRule: @escaping Rule) {
        rule.withLock { $0 = newRule }
    }

    func decide(_ sample: PoseSample, _ context: SwitchContext) -> SwitchDecision {
        let current = rule.withLock { $0 }
        return current(sample, context)
    }
}

/// What one fake decider was asked. A class so the test can read it while the model owns the decider value.
final class DeciderRecorder: Sendable {
    struct State: Sendable {
        var samples: [PoseSample] = []
        var contexts: [SwitchContext] = []
        var resetCount = 0
    }

    let profile: CalibrationProfile
    let settings: SwitchSettings
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(profile: CalibrationProfile, settings: SwitchSettings) {
        self.profile = profile
        self.settings = settings
    }

    var samples: [PoseSample] { state.withLock { $0.samples } }
    var contexts: [SwitchContext] { state.withLock { $0.contexts } }
    var resetCount: Int { state.withLock { $0.resetCount } }

    func record(_ sample: PoseSample, _ context: SwitchContext) {
        state.withLock {
            $0.samples.append(sample)
            $0.contexts.append(context)
        }
    }

    func recordReset() {
        state.withLock { $0.resetCount += 1 }
    }
}

/// A decider that answers from a script and reports to its recorder.
struct FakeDecider: SwitchDeciding {
    let recorder: DeciderRecorder
    let script: DecisionScript

    mutating func process(_ sample: PoseSample, context: SwitchContext) -> SwitchDecision {
        recorder.record(sample, context)
        return script.decide(sample, context)
    }

    mutating func reset() {
        recorder.recordReset()
    }
}

/// An engine with a settable fit result that records every call.
final class FakeSwitchEngine: SwitchEngineMaking {
    struct FitCall: Sendable, Equatable {
        var trace: PoseTrace
        var features: PoseFeatureSet
        var rounds: Set<Int>?
    }

    struct State: Sendable {
        var fitResult: Result<CalibrationProfile, CalibrationError>
        var fitCalls: [FitCall] = []
        var recorders: [DeciderRecorder] = []
    }

    let script = DecisionScript()
    private let state: OSAllocatedUnfairLock<State>

    init(fitResult: Result<CalibrationProfile, CalibrationError> = .success(Fixtures.profile())) {
        state = OSAllocatedUnfairLock(initialState: State(fitResult: fitResult))
    }

    var fitCalls: [FitCall] { state.withLock { $0.fitCalls } }
    /// One recorder per `makeDecider` call, oldest first.
    var recorders: [DeciderRecorder] { state.withLock { $0.recorders } }
    var lastRecorder: DeciderRecorder? { recorders.last }

    func setFitResult(_ result: Result<CalibrationProfile, CalibrationError>) {
        state.withLock { $0.fitResult = result }
    }

    func fitProfile(from trace: PoseTrace, features: PoseFeatureSet, rounds: Set<Int>?) throws -> CalibrationProfile {
        let result = state.withLock { state -> Result<CalibrationProfile, CalibrationError> in
            state.fitCalls.append(FitCall(trace: trace, features: features, rounds: rounds))
            return state.fitResult
        }
        return try result.get()
    }

    func classify(_ pose: HeadPose?, with profile: CalibrationProfile, settings: SwitchSettings) -> PoseClassification {
        .noFace
    }

    func makeDecider(profile: CalibrationProfile, settings: SwitchSettings) -> any SwitchDeciding {
        let recorder = DeciderRecorder(profile: profile, settings: settings)
        state.withLock { $0.recorders.append(recorder) }
        return FakeDecider(recorder: recorder, script: script)
    }
}
