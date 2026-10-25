import Foundation
import SwayModels
import Testing

@testable import SwitchEngine

private let seeds: [UInt64] = [11, 22, 33]

/// Pairs of displays to alternate between, as indices into `ScenarioWorld.ids`.
private let alternations: [[Int]] = [[0, 2], [0, 1], [1, 2]]

/// The six synthetic scenarios of CONTRACT section 6.6, at 15 fps, with the default settings and a profile
/// fitted (by the real engine) from a synthetic labeled trace. The expected counts are the contract's; nothing
/// here is tuned to pass. Each scenario runs for several seeds so a lucky noise draw cannot hide a problem.
@Suite struct SyntheticScenarioTests {
    private let settings = SwitchSettings.default
    private let frame = 1 / ScenarioWorld.frameRate

    // MARK: 1. Noise at one display

    @Test("120 s at one display with twice-the-std noise and 2% face drops: no switches", arguments: [0, 1, 2], seeds)
    func noiseAtOneDisplayNeverSwitches(displayIndex: Int, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let display = ScenarioWorld.ids[displayIndex]
        var script = PoseScript(start: ScenarioWorld.target(display), seed: seed &+ 1)
        script.hold(at: ScenarioWorld.target(display), seconds: 120, noise: 2, dropRate: 0.02)
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: display)

        #expect(run.switches.isEmpty)
        // The drops are really there, and about 2% of the frames.
        let drops = script.samples.filter { $0.pose == nil }.count
        #expect(drops > 0)
        #expect(Double(drops) / Double(script.samples.count) < 0.05)
    }

    // MARK: 2. Ambiguous midpoint

    @Test("60 s at the midpoint between adjacent displays, half-std noise: no switches", arguments: [0, 1], seeds)
    func midpointBetweenAdjacentDisplaysNeverSwitches(pairIndex: Int, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let first = profile.displays[pairIndex]
        let second = profile.displays[pairIndex + 1]
        let midpoint = PoseScript.Target(yaw: (first.yaw + second.yaw) / 2, pitch: (first.pitch + second.pitch) / 2)
        var script = PoseScript(start: midpoint, seed: seed &+ 2)
        script.hold(at: midpoint, seconds: 60, noise: 0.5)
        // Focus unknown, so the margin alone has to hold the line.
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: nil)

        #expect(run.switches.isEmpty)
    }

    // MARK: 3. Glances

    @Test("20 glances of 0.25 s to another display: no switches", arguments: [0, 1, 2], seeds)
    func glancesNeverSwitch(baseIndex: Int, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let base = ScenarioWorld.ids[baseIndex]
        let others = ScenarioWorld.ids.filter { $0 != base }
        var script = PoseScript(start: ScenarioWorld.target(base), seed: seed &+ 3)
        script.hold(at: ScenarioWorld.target(base), seconds: 1)
        for glance in 0..<20 {
            script.hold(at: ScenarioWorld.target(others[glance % 2]), seconds: 0.25)
            script.hold(at: ScenarioWorld.target(base), seconds: 1)
        }
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: base)

        #expect(run.switches.isEmpty)
        // The glances were seen as dwells that ended early, not ignored altogether.
        #expect(run.decisions.contains { if case .dwelling = $0.phase { true } else { false } })
    }

    // MARK: 4. Intentional looks

    @Test("20 intentional looks switch exactly 20 times, each within dwell + 1 frame", arguments: alternations, seeds)
    func intentionalLooksSwitchOncePerLook(pair: [Int], seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let displays = pair.map { ScenarioWorld.ids[$0] }
        var script = PoseScript(start: ScenarioWorld.target(displays[1]), seed: seed &+ 4)
        script.hold(at: ScenarioWorld.target(displays[1]), seconds: 1)
        var looks: [(target: DisplayID, window: Range<Int>)] = []
        for look in 0..<20 {
            let target = displays[look % 2]  // first look goes to displays[0], then back, and so on
            let turn = script.turn(to: ScenarioWorld.target(target), seconds: 0.3)
            let hold = script.hold(at: ScenarioWorld.target(target), seconds: 2)
            looks.append((target, turn.lowerBound..<hold.upperBound))
        }
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: displays[1])

        #expect(run.switches.count == 20)
        for look in looks {
            let inLook = run.switches.filter { look.window.contains($0.index) }
            #expect(inLook.count == 1)
            guard let fired = inLook.first else { continue }
            #expect(fired.display == look.target)

            // First sample of the look that points at the target with at least the enter margin.
            let qualifying = look.window.first { index in
                let classification = run.decisions[index].classification
                return classification.kind == .display && classification.best == look.target
                    && classification.margin >= settings.enterMargin
            }
            let start = try #require(qualifying)
            let latency = fired.time - script.samples[start].timestamp
            #expect(latency >= settings.dwell - SwitchStateMachine.timeTolerance)
            #expect(latency <= settings.dwell + frame)
        }
    }

    // MARK: 5. Transit through the middle display

    @Test(
        "0.25 s transit across the middle display: exactly one switch, to the far display", arguments: [true, false],
        seeds)
    func transitThroughTheMiddleDisplaySwitchesOnlyToTheFarOne(leftToRight: Bool, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let origin = leftToRight ? ScenarioWorld.left : ScenarioWorld.right
        let destination = leftToRight ? ScenarioWorld.right : ScenarioWorld.left
        var script = PoseScript(start: ScenarioWorld.target(origin), seed: seed &+ 5)
        script.hold(at: ScenarioWorld.target(origin), seconds: 1)
        script.turn(to: ScenarioWorld.target(destination), seconds: 0.25)
        script.hold(at: ScenarioWorld.target(destination), seconds: 2)
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: origin)

        #expect(run.switches.map(\.display) == [destination])
        // The transit really did start a dwell on the middle display, which was then abandoned.
        let middleDwells = run.decisions.filter { decision in
            if case .dwelling(let display, _) = decision.phase { return display == ScenarioWorld.middle }
            return false
        }
        #expect(!middleDwells.isEmpty)
    }

    // MARK: 6. Keyboard

    @Test("A 2 s look 40 degrees down: no switches, and the reason is elsewhere", arguments: [0, 1, 2], seeds)
    func lookingDownAtTheKeyboardIsElsewhere(displayIndex: Int, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let display = ScenarioWorld.ids[displayIndex]
        let screen = ScenarioWorld.target(display)
        let keyboard = PoseScript.Target(yaw: screen.yaw, pitch: screen.pitch - 40)
        var script = PoseScript(start: screen, seed: seed &+ 6)
        script.hold(at: screen, seconds: 1)
        script.turn(to: keyboard, seconds: 0.3)
        let look = script.hold(at: keyboard, seconds: 2)
        script.turn(to: screen, seconds: 0.3)
        script.hold(at: screen, seconds: 1)
        let run = ScenarioRunner.run(script.samples, profile: profile, initialFocus: display)

        #expect(run.switches.isEmpty)
        #expect(look.count == 30)
        for index in look {
            #expect(run.decisions[index].reason == .elsewhere)
            #expect(run.decisions[index].classification.kind == .elsewhere)
        }
    }
}
