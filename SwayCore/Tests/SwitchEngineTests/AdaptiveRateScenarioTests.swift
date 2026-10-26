import Foundation
import SwayModels
import Testing

@testable import SwitchEngine

private let seeds: [UInt64] = [11, 22, 33]

/// The adaptive frame rate (CONTRACT 6.2.1, SPEC D45) seen from the switch decider: the poses it receives are the
/// ones that survive the thinning, so these scenarios thin a 15 fps stream the way `LivePoseSource` does and replay
/// the rest through the real engine.
///
/// `PoseEstimator` is not importable here, so `AdaptiveRateModel` restates the contract's rule for `.adaptive`
/// demand independently of the production type. The properties checked are the ones that matter for switching:
/// - while a face has been seen within 2 s, nothing is thinned, so the switching speed is unchanged;
/// - after an absence the first face is picked up within one throttled interval, and the switch that follows fires
///   within `dwell` plus one sample interval of the first qualifying sample.
@Suite struct AdaptiveRateScenarioTests {
    private let settings = SwitchSettings.default
    private let frame = 1 / ScenarioWorld.frameRate
    /// Timestamps are large in the app (host uptime), so the scenarios are shifted to a realistic value.
    private let uptime = 300_000.0

    /// The contract's thinning of a stream under `.adaptive` demand, on a device that delivers every frame given:
    /// the minimum gap between processed frames is 1/15 s (1/10 s power constrained) while a face was seen within 2 s
    /// and 1/5 s (1/2 s) otherwise, with a 4 ms tolerance. The first frame counts as a face just seen.
    private struct AdaptiveRateModel {
        var powerConstrained: Bool

        func thin(_ frames: [PoseSample]) -> [PoseSample] {
            var kept: [PoseSample] = []
            var lastKept: Double?
            var lastFace = frames.first?.timestamp ?? 0
            for sample in frames {
                if let last = lastKept {
                    let faceRecent = sample.timestamp - lastFace < 2
                    let interval =
                        faceRecent
                        ? (powerConstrained ? 1.0 / 10 : 1.0 / 15)
                        : (powerConstrained ? 1.0 / 2 : 1.0 / 5)
                    if sample.timestamp - last < interval - 0.004 { continue }
                }
                kept.append(sample)
                lastKept = sample.timestamp
                if sample.pose != nil { lastFace = sample.timestamp }
            }
            return kept
        }
    }

    private func shifted(_ samples: [PoseSample]) -> [PoseSample] {
        samples.map { PoseSample(timestamp: $0.timestamp + uptime, pose: $0.pose) }
    }

    /// Replaces the poses at `indices` by "no face", as if the person had left.
    private func blanked(_ samples: [PoseSample], _ indices: Range<Int>) -> [PoseSample] {
        var result = samples
        for index in indices { result[index].pose = nil }
        return result
    }

    /// The index of the first sample at or after `from` that points at `target` with at least the enter margin.
    private func firstQualifying(
        in samples: [PoseSample], run: ScenarioRun, target: DisplayID, from: Int = 0
    ) -> Int? {
        samples.indices.first { index in
            let classification = run.decisions[index].classification
            return index >= from && classification.kind == .display && classification.best == target
                && classification.margin >= settings.enterMargin
        }
    }

    // MARK: A face present: nothing is thinned

    @Test("10 looks with single-frame drops and 1.5 s off-camera pauses: no frame is thinned, switching is unchanged")
    func switchingWithAFaceIsNotSlowedDown() throws {
        for seed in seeds {
            let profile = try ScenarioWorld.profile(seed: seed)
            let displays = [ScenarioWorld.left, ScenarioWorld.right]
            var script = PoseScript(start: ScenarioWorld.target(displays[1]), seed: seed &+ 21)
            script.hold(at: ScenarioWorld.target(displays[1]), seconds: 1)
            var looks: [(target: DisplayID, window: Range<Int>)] = []
            var pauses: [Range<Int>] = []
            for look in 0..<10 {
                let target = displays[look % 2]
                let turn = script.turn(to: ScenarioWorld.target(target), seconds: 0.3)
                let hold = script.hold(at: ScenarioWorld.target(target), seconds: 2, dropRate: 0.02)
                looks.append((target, turn.lowerBound..<hold.upperBound))
                if look % 2 == 1 {
                    // The face is lost for 1.5 s, less than the 2 s after which the rate would drop.
                    pauses.append(script.hold(at: ScenarioWorld.target(target), seconds: 1.5))
                }
            }
            let frames = shifted(pauses.reduce(script.samples) { blanked($0, $1) })

            // Every frame survives: a face was always seen within the last 2 s.
            let thinned = AdaptiveRateModel(powerConstrained: false).thin(frames)
            #expect(thinned == frames)

            let thinnedRun = ScenarioRunner.run(thinned, profile: profile, initialFocus: displays[1])
            let plainRun = ScenarioRunner.run(frames, profile: profile, initialFocus: displays[1])
            #expect(thinnedRun.switches == plainRun.switches)
            #expect(thinnedRun.switches.count == 10)

            for look in looks {
                let fired = try #require(thinnedRun.switches.first { look.window.contains($0.index) })
                #expect(fired.display == look.target)
                let start = try #require(
                    firstQualifying(in: frames, run: thinnedRun, target: look.target, from: look.window.lowerBound))
                let latency = fired.time - frames[start].timestamp
                #expect(latency >= settings.dwell - SwitchStateMachine.timeTolerance)
                #expect(latency <= settings.dwell + frame + SwitchStateMachine.timeTolerance)
            }
        }
    }

    // MARK: Away, then back

    struct AwayCase: Sendable, CustomTestStringConvertible {
        var powerConstrained: Bool
        var awayFrames: Int
        var seed: UInt64

        var testDescription: String {
            "\(powerConstrained ? "power constrained" : "normal"), away \(awayFrames) frames, seed \(seed)"
        }
    }

    /// 10 s of absence plus 0 to 7 frames, so the face returns at every phase of the 3-frame (5 fps) and 8-frame
    /// (2 fps) sampling grids.
    static let awayCases: [AwayCase] = [false, true].flatMap { constrained in
        (150..<158).flatMap { frames in
            seeds.map { AwayCase(powerConstrained: constrained, awayFrames: frames, seed: $0) }
        }
    }

    @Test(
        "A switch after 10 s away fires within dwell of the first qualifying sample and 1 s + dwell of the return",
        arguments: awayCases)
    func switchingAfterAnAbsence(_ scenario: AwayCase) throws {
        let profile = try ScenarioWorld.profile(seed: scenario.seed)
        let origin = ScenarioWorld.left
        let target = ScenarioWorld.right
        var script = PoseScript(start: ScenarioWorld.target(origin), seed: scenario.seed &+ 22)
        script.hold(at: ScenarioWorld.target(origin), seconds: 2)
        // The person leaves (no face) and comes back looking at the other display.
        let away = script.hold(at: ScenarioWorld.target(target), seconds: Double(scenario.awayFrames) / 15)
        script.hold(at: ScenarioWorld.target(target), seconds: 3)
        let frames = shifted(blanked(script.samples, away))
        let returnTime = frames[away.upperBound].timestamp

        let thinned = AdaptiveRateModel(powerConstrained: scenario.powerConstrained).thin(frames)
        let run = ScenarioRunner.run(thinned, profile: profile, initialFocus: origin)

        // The absence really was throttled: sparse samples after the first 2 s (and at least one per interval).
        let awayTimes = thinned.map(\.timestamp).filter {
            $0 >= frames[away.lowerBound].timestamp + 2.6 && $0 < returnTime
        }
        let interval = scenario.powerConstrained ? 0.5 : 0.2
        #expect(awayTimes.count > 5)
        for (earlier, later) in zip(awayTimes, awayTimes.dropFirst()) {
            #expect(later - earlier >= interval - 0.004 - 1e-6)
            #expect(later - earlier <= interval + frame + 1e-6)
        }
        #expect(thinned.count < frames.count - 40)

        // Exactly one switch, to the display the person came back to, and none while they were away.
        #expect(run.switches.count == 1)
        let fired = try #require(run.switches.first)
        #expect(fired.display == target)
        #expect(fired.time > returnTime)

        // It fires at the dwell plus at most one sample interval after the first qualifying sample...
        let firstFace = try #require(thinned.firstIndex { $0.timestamp >= returnTime })
        let qualifying = try #require(firstQualifying(in: thinned, run: run, target: target, from: firstFace))
        let latency = fired.time - thinned[qualifying].timestamp
        // A 1/10 s interval is every second frame of a 15 fps device, so the sample interval is 2 frames there.
        let sampleInterval = scenario.powerConstrained ? 2 * frame : frame
        #expect(latency >= settings.dwell - SwitchStateMachine.timeTolerance)
        #expect(latency <= settings.dwell + sampleInterval + SwitchStateMachine.timeTolerance)

        // ...and within 1 s plus the dwell of the face returning.
        #expect(fired.time - returnTime <= 1 + settings.dwell)
    }

    @Test("A face that returns to the focused display never switches", arguments: [false, true], seeds)
    func returningToTheFocusedDisplayDoesNothing(powerConstrained: Bool, seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let origin = ScenarioWorld.middle
        var script = PoseScript(start: ScenarioWorld.target(origin), seed: seed &+ 23)
        script.hold(at: ScenarioWorld.target(origin), seconds: 2)
        let away = script.hold(at: ScenarioWorld.target(origin), seconds: 10)
        script.hold(at: ScenarioWorld.target(origin), seconds: 3)
        let frames = shifted(blanked(script.samples, away))

        let thinned = AdaptiveRateModel(powerConstrained: powerConstrained).thin(frames)
        let run = ScenarioRunner.run(thinned, profile: profile, initialFocus: origin)

        #expect(thinned.count < frames.count - 40)
        #expect(run.switches.isEmpty)
        // While away every sample says no face.
        var awayReasons: [SwitchHoldReason?] = []
        for (sample, decision) in zip(thinned, run.decisions) where sample.pose == nil {
            awayReasons.append(decision.reason)
        }
        #expect(!awayReasons.isEmpty)
        #expect(awayReasons.allSatisfy { $0 == .noFace })
    }

    // MARK: Power constrained, face present

    @Test("Power constrained with a face present, 10 looks still switch, within dwell + 2 frames", arguments: seeds)
    func powerConstrainedSwitchingWithAFace(seed: UInt64) throws {
        let profile = try ScenarioWorld.profile(seed: seed)
        let displays = [ScenarioWorld.left, ScenarioWorld.right]
        var script = PoseScript(start: ScenarioWorld.target(displays[1]), seed: seed &+ 24)
        script.hold(at: ScenarioWorld.target(displays[1]), seconds: 1)
        var looks: [(target: DisplayID, window: Range<Int>)] = []
        for look in 0..<10 {
            let target = displays[look % 2]
            let turn = script.turn(to: ScenarioWorld.target(target), seconds: 0.3)
            let hold = script.hold(at: ScenarioWorld.target(target), seconds: 2)
            looks.append((target, turn.lowerBound..<hold.upperBound))
        }
        let frames = shifted(script.samples)
        let thinned = AdaptiveRateModel(powerConstrained: true).thin(frames)
        let run = ScenarioRunner.run(thinned, profile: profile, initialFocus: displays[1])

        // Every second frame of the 15 fps device.
        #expect(abs(thinned.count - frames.count / 2) <= 1)
        #expect(run.switches.count == 10)
        for look in looks {
            let lookStart = frames[look.window.lowerBound].timestamp
            let lookEnd = frames[look.window.upperBound - 1].timestamp
            let fired = try #require(run.switches.first { $0.time >= lookStart && $0.time <= lookEnd })
            #expect(fired.display == look.target)
            let from = try #require(thinned.firstIndex { $0.timestamp >= lookStart })
            let qualifying = try #require(firstQualifying(in: thinned, run: run, target: look.target, from: from))
            let latency = fired.time - thinned[qualifying].timestamp
            #expect(latency >= settings.dwell - SwitchStateMachine.timeTolerance)
            #expect(latency <= settings.dwell + 2 * frame + SwitchStateMachine.timeTolerance)
        }
    }
}
