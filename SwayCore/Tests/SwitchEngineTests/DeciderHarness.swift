import SwayModels

@testable import SwitchEngine

/// Feeds samples to a state machine with a mutable context, for readable rule tests.
struct DeciderHarness {
    var machine: SwitchStateMachine
    var context: SwitchContext

    init(settings: SwitchSettings = HandProfile.settings, focused: DisplayID? = HandProfile.b) {
        machine = SwitchStateMachine(profile: HandProfile.profile, settings: settings)
        context = SwitchContext(focusedDisplay: focused)
    }

    /// Processes one sample at time `t`; `yaw == nil` means no face.
    @discardableResult
    mutating func feed(_ t: Double, _ yaw: Double?, confidence: Double = 0.95) -> SwitchDecision {
        machine.process(makeSample(t, yaw: yaw, confidence: confidence), context: context)
    }

    /// Processes a steady stream of samples with the same yaw, `start` through `end` inclusive. Never skips a
    /// frame, so no test depends on how the machine treats a hole in the timestamps.
    @discardableResult
    mutating func run(from start: Double, to end: Double, _ yaw: Double?, step: Double = 0.125) -> [SwitchDecision] {
        var decisions: [SwitchDecision] = []
        for t in stride(from: start, through: end, by: step) {
            decisions.append(feed(t, yaw))
        }
        return decisions
    }
}
