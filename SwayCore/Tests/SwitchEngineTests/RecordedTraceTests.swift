import Foundation
import SwayModels
import Testing

@testable import SwitchEngine

/// The user's real M1 gate recording (numbers only): 3 displays x 2 rounds x 75 samples, segments 1.6 s apart,
/// recorded on a C922 on 2026-10-24. Fit on one round, replay the other.
@Suite struct RecordedTraceTests {
    private let engine = PoseSwitchEngine()
    private let settings = SwitchSettings.default
    private let oneFrame = 1 / SwayPolicy.defaultFrameRate

    private func loadTrace() throws -> PoseTrace {
        let url = try #require(
            Bundle.module.url(
                forResource: "gate-trace-2026-10-24", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PoseTrace.self, from: Data(contentsOf: url))
    }

    private func segments(of trace: PoseTrace, round: Int) -> [TraceSegment] {
        trace.segments.filter { $0.round == round }
    }

    @Test func fixtureHasTheDocumentedShape() throws {
        let trace = try loadTrace()
        #expect(trace.segments.count == 6)
        #expect(trace.segments.allSatisfy { $0.samples.count == 75 && $0.displayID != nil })
        #expect(Set(trace.segments.compactMap(\.displayID)).count == 3)
        #expect(segments(of: trace, round: 1).count == 3)
        #expect(segments(of: trace, round: 2).count == 3)
        #expect(trace.layout?.displays.count == 3)
        #expect(trace.cameraName == "C922 Pro Stream Webcam")
    }

    @Test(arguments: [(fit: 1, replay: 2), (fit: 2, replay: 1)])
    func replayingTheOtherRoundSwitchesExactlyTwiceAtTheRightTimes(fit: Int, replay: Int) throws {
        let trace = try loadTrace()
        let profile = try engine.fitProfile(from: trace, features: .visionAngles, rounds: [fit])
        #expect(profile.displays.count == 3)

        let roundSegments = segments(of: trace, round: replay)
        let first = try #require(roundSegments.first?.displayID)
        var decider = engine.makeDecider(profile: profile, settings: settings)
        var focused: DisplayID? = first
        var switches: [(time: Double, display: DisplayID)] = []
        for segment in roundSegments {
            for sample in segment.samples {
                let decision = decider.process(sample, context: SwitchContext(focusedDisplay: focused))
                if let target = decision.switchTo {
                    switches.append((sample.timestamp, target))
                    focused = target
                }
            }
        }

        // Exactly two switches: to the 2nd and the 3rd segment's display, and no others.
        #expect(switches.count == 2)
        let expected = roundSegments.dropFirst().compactMap(\.displayID)
        #expect(switches.map(\.display) == expected)
        for (fired, segment) in zip(switches, roundSegments.dropFirst()) {
            guard let segmentStart = segment.samples.first?.timestamp else {
                Issue.record("segment without samples")
                continue
            }
            let latency = fired.time - segmentStart
            #expect(latency >= settings.dwell - SwitchStateMachine.timeTolerance)
            #expect(latency <= settings.dwell + oneFrame)
        }
    }

    @Test(arguments: [(fit: 1, test: 2), (fit: 2, test: 1)])
    func atLeastNinetyNinePercentOfTheHeldOutRoundClassifiesAsItsOwnDisplay(fit: Int, test: Int) throws {
        let trace = try loadTrace()
        let profile = try engine.fitProfile(from: trace, features: .visionAngles, rounds: [fit])
        var total = 0
        var correct = 0
        for segment in segments(of: trace, round: test) {
            for sample in segment.samples {
                total += 1
                let result = engine.classify(sample.pose, with: profile, settings: settings)
                if result.kind == .display && result.best == segment.displayID { correct += 1 }
            }
        }
        #expect(total == 225)
        #expect(Double(correct) / Double(total) >= 0.99)
    }

    @Test func theProfileMatchesTheRecordedLayoutAndCamera() throws {
        let trace = try loadTrace()
        let layout = try #require(trace.layout)
        let profile = try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
        #expect(profile.matches(layout))
        #expect(profile.cameraName == trace.cameraName)
        #expect(profile.displays.map(\.displayID) == layout.displays.map(\.id))
        #expect(profile.pitchScale >= profile.yawScale)
    }
}
