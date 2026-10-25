import Foundation
import SwayModels
import Testing

@testable import SwitchEngine

/// The public facade: it must do exactly what the internal pieces do and share no state between deciders.
@Suite struct PoseSwitchEngineTests {
    private let engine = PoseSwitchEngine()

    @Test func fitProfileMatchesTheFitter() throws {
        let trace = ScenarioWorld.calibrationTrace(seed: 5)
        let viaEngine = try engine.fitProfile(from: trace, features: .visionAngles, rounds: [1])
        let viaFitter = try ProfileFitter().fit(from: trace, features: .visionAngles, rounds: [1])
        #expect(viaEngine == viaFitter)
    }

    @Test func classifyMatchesTheClassifier() {
        let pose = makePose(yaw: 51, pitch: 8)
        let viaEngine = engine.classify(pose, with: HandProfile.profile, settings: HandProfile.settings)
        let viaClassifier = PoseClassifier(profile: HandProfile.profile, settings: HandProfile.settings).classify(pose)
        #expect(viaEngine == viaClassifier)
        #expect(engine.classify(nil, with: HandProfile.profile, settings: HandProfile.settings) == .noFace)
    }

    @Test func aNewDeciderIsIdle() {
        var decider = engine.makeDecider(profile: HandProfile.profile, settings: HandProfile.settings)
        let decision = decider.process(makeSample(0, yaw: nil), context: SwitchContext(focusedDisplay: nil))
        #expect(decision.phase == .idle)
        #expect(decision.reason == .noFace)
        #expect(decision.switchTo == nil)
    }

    @Test func decidersFromOneEngineDoNotShareState() {
        var first = engine.makeDecider(profile: HandProfile.profile, settings: HandProfile.settings)
        var second = engine.makeDecider(profile: HandProfile.profile, settings: HandProfile.settings)
        let context = SwitchContext(focusedDisplay: HandProfile.b)
        _ = first.process(makeSample(0, yaw: HandProfile.yawA), context: context)
        _ = first.process(makeSample(0.25, yaw: HandProfile.yawA), context: context)
        // The second decider starts its own dwell at 0.375; the first one would be at progress 0.75.
        let decision = second.process(makeSample(0.375, yaw: HandProfile.yawA), context: context)
        #expect(decision.phase == .dwelling(display: HandProfile.a, progress: 0))
    }

    @Test func aDeciderUsesTheSettingsItWasMadeWith() {
        var slow = HandProfile.settings
        slow.dwell = 1
        var decider = engine.makeDecider(profile: HandProfile.profile, settings: slow)
        let context = SwitchContext(focusedDisplay: HandProfile.b)
        var fired: [Double] = []
        for step in 0...8 {
            let t = Double(step) * 0.125
            if decider.process(makeSample(t, yaw: HandProfile.yawA), context: context).switchTo != nil {
                fired.append(t)
            }
        }
        #expect(fired == [1.0])
    }

    @Test func resetThroughTheProtocolDropsTheDwell() {
        var decider = engine.makeDecider(profile: HandProfile.profile, settings: HandProfile.settings)
        let context = SwitchContext(focusedDisplay: HandProfile.b)
        _ = decider.process(makeSample(0, yaw: HandProfile.yawA), context: context)
        decider.reset()
        let decision = decider.process(makeSample(0.25, yaw: HandProfile.yawA), context: context)
        #expect(decision.phase == .dwelling(display: HandProfile.a, progress: 0))
    }

    @Test func theEngineCanBeSharedAcrossTasks() async {
        let shared = engine
        async let one = Task.detached {
            shared.classify(makePose(yaw: 60, pitch: 8), with: HandProfile.profile, settings: .default).best
        }.value
        async let two = Task.detached {
            shared.classify(makePose(yaw: 0, pitch: 8), with: HandProfile.profile, settings: .default).best
        }.value
        #expect(await one == HandProfile.a)
        #expect(await two == HandProfile.c)
    }
}
