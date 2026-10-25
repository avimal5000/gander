import SwayModels
import Testing

@testable import SwayUI

@Suite("Pose history")
struct PoseHistoryTests {
    @Test func fpsIsSamplesPerSecondOverTheLastTwoSeconds() {
        var history = PoseHistory()
        for index in 0..<90 {
            history.append(Fixtures.sample(at: Double(index) / 15))
        }
        #expect(abs(history.fps - 15) < 0.001)
    }

    @Test func fpsFollowsARateChange() {
        var history = PoseHistory()
        var time = 0.0
        for _ in 0..<60 {
            history.append(Fixtures.sample(at: time))
            time += 1.0 / 30
        }
        #expect(abs(history.fps - 30) < 0.001)
        // Slow down to 10 fps for longer than the 2 s window.
        for _ in 0..<30 {
            history.append(Fixtures.sample(at: time))
            time += 0.1
        }
        #expect(abs(history.fps - 10) < 0.001)
    }

    @Test func fpsIsZeroWithFewerThanTwoSamples() {
        var history = PoseHistory()
        #expect(history.fps == 0)
        history.append(Fixtures.sample(at: 1))
        #expect(history.fps == 0)
    }

    @Test func fpsCountsFramesWithoutAFace() {
        var history = PoseHistory()
        for index in 0..<31 {
            history.append(Fixtures.sample(at: Double(index) / 15, face: index.isMultiple(of: 2)))
        }
        #expect(abs(history.fps - 15) < 0.001)
    }

    @Test func plotKeepsOnlyTheLastTenSecondsOfFaceSamples() {
        var history = PoseHistory()
        for index in 0..<300 {
            history.append(Fixtures.sample(at: Double(index) / 15, face: true))
        }
        let newest = 299.0 / 15
        #expect(history.points.allSatisfy { $0.timestamp >= newest - PoseHistory.plotWindow })
        #expect(history.points.last?.timestamp == newest)
        #expect(history.points.count >= 150)
        #expect(history.points.count <= 152)
    }

    @Test func framesWithoutAFaceLeaveAGapInThePlot() {
        var history = PoseHistory()
        history.append(Fixtures.sample(at: 0, face: true))
        history.append(Fixtures.sample(at: 0.1, face: false))
        history.append(Fixtures.sample(at: 0.2, face: true))
        #expect(history.points.count == 2)
        #expect(history.points.map(\.id) == [0, 1])
    }

    @Test func aBackwardsTimestampRestartsTheHistory() {
        var history = PoseHistory()
        for index in 0..<10 { history.append(Fixtures.sample(at: 100 + Double(index) / 15)) }
        history.append(Fixtures.sample(at: 5))
        #expect(history.points.count == 1)
        #expect(history.fps == 0)
    }

    @Test func resetForgetsEverything() {
        var history = PoseHistory()
        for index in 0..<10 { history.append(Fixtures.sample(at: Double(index) / 15)) }
        history.reset()
        #expect(history.points.isEmpty)
        #expect(history.fps == 0)
    }
}
