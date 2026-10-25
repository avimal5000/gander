import Foundation
import SwayModels

@testable import SwitchEngine

/// The outcome of replaying a pose stream through a decider.
struct ScenarioRun {
    struct Switch: Equatable {
        /// Index of the sample that completed the dwell.
        var index: Int
        var time: Double
        var display: DisplayID
    }

    var decisions: [SwitchDecision]
    var switches: [Switch]
}

/// Replays samples through a decider made by the real engine, with perfect focus: after each switch the
/// focused display becomes the switch target on the next sample.
enum ScenarioRunner {
    static func run(
        _ samples: [PoseSample],
        profile: CalibrationProfile,
        settings: SwitchSettings = .default,
        initialFocus: DisplayID?,
        targets: Set<DisplayID>? = nil
    ) -> ScenarioRun {
        var decider = PoseSwitchEngine().makeDecider(profile: profile, settings: settings)
        var focused = initialFocus
        var decisions: [SwitchDecision] = []
        var switches: [ScenarioRun.Switch] = []
        for (index, sample) in samples.enumerated() {
            let context = SwitchContext(focusedDisplay: focused, isFocusLocked: false, targets: targets)
            let decision = decider.process(sample, context: context)
            decisions.append(decision)
            if let target = decision.switchTo {
                switches.append(ScenarioRun.Switch(index: index, time: sample.timestamp, display: target))
                focused = target
            }
        }
        return ScenarioRun(decisions: decisions, switches: switches)
    }
}
