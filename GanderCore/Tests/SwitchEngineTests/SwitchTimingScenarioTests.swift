import Foundation
import GanderModels
import Testing

@testable import SwitchEngine

private let seeds: [UInt64] = [11, 22, 33]

/// The adjustable switching timing (SPEC D49, F35) seen from the decider, at 15 fps with a profile fitted by the real
/// engine: the settings come from `SwitchSensitivity`, as the app builds them.
///
/// The decider starts no new dwell until the cooldown is over (step 3 of CONTRACT section 6.6), so a quick look back
/// switches `cooldown + dwell` after the first switch, with each of the two rounded up to whole frames. The default
/// is 0.75 s + 0.4 s (18 frames, 1.2 s) and the Instant preset 0.3 s + 0.1 s (7 frames, about 0.47 s).
@Suite struct SwitchTimingScenarioTests {
    private let frame = 1 / ScenarioWorld.frameRate
    private let defaultTiming = SwitchSensitivity.default.switchSettings()
    private let instantTiming = SwitchSensitivity.instant.switchSettings()

    /// A switch from the right display to the middle one, followed at once by a held look back at the right one.
    private struct QuickReturn {
        var switches: [ScenarioRun.Switch]

        /// Seconds from the first switch to the second.
        var gap: Double { switches[1].time - switches[0].time }
    }

    /// The head goes to the middle display and, on the sample after the first switch fires, turns back to the right
    /// display and stays there. So the cooldown, not the script, decides when the second switch can start.
    private func quickReturn(_ settings: SwitchSettings, seed: UInt64) throws -> QuickReturn {
        let profile = try ScenarioWorld.profile(seed: seed)
        let home = ScenarioWorld.right
        let away = ScenarioWorld.middle
        func scriptUpToTheLook() -> PoseScript {
            var script = PoseScript(start: ScenarioWorld.target(home), seed: seed &+ 7)
            script.hold(at: ScenarioWorld.target(home), seconds: 1)
            script.turn(to: ScenarioWorld.target(away), seconds: 0.1)
            return script
        }

        // Where the first switch fires when the head stays on the middle display.
        var probe = scriptUpToTheLook()
        probe.hold(at: ScenarioWorld.target(away), seconds: 3)
        let probed = ScenarioRunner.run(probe.samples, profile: profile, settings: settings, initialFocus: home)
        let first = try #require(probed.switches.first)

        // The same samples up to that switch, then the look back.
        var script = scriptUpToTheLook()
        let awayFrames = first.index + 1 - script.samples.count
        #expect(awayFrames >= 0)
        script.hold(at: ScenarioWorld.target(away), seconds: Double(max(0, awayFrames)) / ScenarioWorld.frameRate)
        let turnBack = script.turn(to: ScenarioWorld.target(home), seconds: 0.1)
        script.hold(at: ScenarioWorld.target(home), seconds: 4)
        let run = ScenarioRunner.run(script.samples, profile: profile, settings: settings, initialFocus: home)

        #expect(run.switches.map(\.display) == [away, home])
        #expect(run.switches.first == first, "Nothing before the look back changed")
        #expect(turnBack.lowerBound == first.index + 1, "The look back follows the first switch at once")
        return QuickReturn(switches: run.switches)
    }

    // MARK: A quick look back

    @Test(
        "Default timing: a held look back switches back about cooldown + dwell after the first switch", arguments: seeds
    )
    func aQuickReturnWithTheDefaultTimingTakesTheCooldownPlusTheDwell(seed: UInt64) throws {
        #expect(defaultTiming == .default)
        let result = try quickReturn(defaultTiming, seed: seed)

        let expected = defaultTiming.cooldown + defaultTiming.dwell
        #expect(result.gap >= expected - SwitchStateMachine.timeTolerance)
        #expect(result.gap <= expected + 2 * frame)
        #expect(abs(result.gap - 1.2) < frame / 2, "18 frames")
    }

    @Test("Instant timing: a held look back switches back about 0.4 s after the first switch", arguments: seeds)
    func aQuickReturnWithTheInstantPresetIsAboutFourTenthsOfASecond(seed: UInt64) throws {
        #expect(instantTiming.dwell == 0.10)
        #expect(instantTiming.cooldown == 0.30)
        let result = try quickReturn(instantTiming, seed: seed)

        let expected = instantTiming.cooldown + instantTiming.dwell
        #expect(result.gap >= expected - SwitchStateMachine.timeTolerance)
        #expect(result.gap <= expected + 2 * frame)
        #expect(abs(result.gap - 7 * frame) < frame / 2, "7 frames")
    }

    @Test("The Instant preset returns more than twice as fast as the default", arguments: seeds)
    func theInstantPresetIsFasterThanTheDefault(seed: UInt64) throws {
        let slow = try quickReturn(defaultTiming, seed: seed)
        let fast = try quickReturn(instantTiming, seed: seed)

        #expect(fast.gap < slow.gap / 2)
        #expect(slow.gap - fast.gap > 0.6)
    }

    @Test("Every pause from the shortest to the longest delays the return by that pause", arguments: [0.2, 0.75, 1.5])
    func theReturnWaitsForTheWholePause(cooldown: Double) throws {
        let settings = SwitchSensitivity(dwell: 0.10, cooldown: cooldown, confidenceLevel: 2).switchSettings()
        #expect(settings.cooldown == cooldown)
        let result = try quickReturn(settings, seed: 22)

        #expect(result.gap >= cooldown + 0.10 - SwitchStateMachine.timeTolerance)
        #expect(result.gap <= cooldown + 0.10 + 2 * frame)
    }

    // MARK: A sweep through the middle display

    @Test(
        "0.2 s and 0.25 s sweeps across the middle display: one switch, to the far display, with the Instant preset",
        arguments: [true, false], seeds)
    func aFastSweepStillSkipsTheMiddleDisplayWithTheInstantPreset(leftToRight: Bool, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let origin = leftToRight ? ScenarioWorld.left : ScenarioWorld.right
        let destination = leftToRight ? ScenarioWorld.right : ScenarioWorld.left
        // Each sweep is over the middle display for less than the 0.10 s hold time.
        for sweep in [0.2, 0.25] {
            var script = PoseScript(start: ScenarioWorld.target(origin), seed: seed &+ 8)
            script.hold(at: ScenarioWorld.target(origin), seconds: 1)
            script.turn(to: ScenarioWorld.target(destination), seconds: sweep)
            script.hold(at: ScenarioWorld.target(destination), seconds: 2)
            let run = ScenarioRunner.run(
                script.samples, profile: profile, settings: instantTiming, initialFocus: origin)

            #expect(run.switches.map(\.display) == [destination], "\(sweep) s sweep")
            // The sweep really did start a dwell on the middle display, which was then abandoned.
            let middleDwells = run.decisions.filter { decision in
                if case .dwelling(let display, _) = decision.phase { return display == ScenarioWorld.middle }
                return false
            }
            #expect(!middleDwells.isEmpty, "\(sweep) s sweep")
        }
    }

    @Test(
        "A 0.3 s rest on the middle display is a glance by default and a switch with the Instant preset",
        arguments: seeds)
    func aShortRestOnTheMiddleDisplayDependsOnTheHoldTime(seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        var script = PoseScript(start: ScenarioWorld.target(ScenarioWorld.left), seed: seed &+ 9)
        script.hold(at: ScenarioWorld.target(ScenarioWorld.left), seconds: 1)
        script.turn(to: ScenarioWorld.target(ScenarioWorld.middle), seconds: 0.15)
        script.hold(at: ScenarioWorld.target(ScenarioWorld.middle), seconds: 0.3)
        script.turn(to: ScenarioWorld.target(ScenarioWorld.right), seconds: 0.15)
        script.hold(at: ScenarioWorld.target(ScenarioWorld.right), seconds: 2)

        let byDefault = ScenarioRunner.run(
            script.samples, profile: profile, settings: defaultTiming, initialFocus: ScenarioWorld.left)
        let instant = ScenarioRunner.run(
            script.samples, profile: profile, settings: instantTiming, initialFocus: ScenarioWorld.left)

        #expect(byDefault.switches.map(\.display) == [ScenarioWorld.right])
        #expect(instant.switches.map(\.display) == [ScenarioWorld.middle, ScenarioWorld.right])
    }
}
