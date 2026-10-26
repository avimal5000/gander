import Foundation
import SwayModels
import Testing

@testable import PoseEstimator

/// The pure frame-rate rule of CONTRACT 6.2.1. The expected numbers are written out here (1/15 s, 1/10 s, 1/5 s,
/// 1/2 s, a 2 s absence, a 4 ms tolerance) and do not read the production constants, so a wrong constant fails.
@Suite("AdaptiveFrameRate")
struct AdaptiveFrameRateTests {
    private let tolerance = 0.004
    private let epsilon = 1e-9

    /// One row of the interval table, by whether a face was seen within the last 2 s.
    struct Row: Sendable, CustomTestStringConvertible {
        var demand: PoseDemand
        var constrained: Bool
        var faceRecent: Bool
        var interval: TimeInterval

        var testDescription: String {
            "\(demand), \(constrained ? "power constrained" : "no constraint"), "
                + "\(faceRecent ? "face within 2 s" : "no face for 2 s")"
        }
    }

    static let table: [Row] = [
        Row(demand: .full, constrained: false, faceRecent: true, interval: 1.0 / 15),
        Row(demand: .full, constrained: false, faceRecent: false, interval: 1.0 / 15),
        Row(demand: .full, constrained: true, faceRecent: true, interval: 1.0 / 15),
        Row(demand: .full, constrained: true, faceRecent: false, interval: 1.0 / 15),
        Row(demand: .adaptive, constrained: false, faceRecent: true, interval: 1.0 / 15),
        Row(demand: .adaptive, constrained: false, faceRecent: false, interval: 1.0 / 5),
        Row(demand: .adaptive, constrained: true, faceRecent: true, interval: 1.0 / 10),
        Row(demand: .adaptive, constrained: true, faceRecent: false, interval: 1.0 / 2),
        Row(demand: .reduced, constrained: false, faceRecent: true, interval: 1.0 / 5),
        Row(demand: .reduced, constrained: false, faceRecent: false, interval: 1.0 / 5),
        Row(demand: .reduced, constrained: true, faceRecent: true, interval: 1.0 / 2),
        Row(demand: .reduced, constrained: true, faceRecent: false, interval: 1.0 / 2),
    ]

    /// A rate in the state of `row`, whose first frame was processed at 100 and had a face. Frames at 101 are then
    /// within 2 s of that face and frames at 105 are not.
    private func makeRate(_ row: Row) -> AdaptiveFrameRate {
        var rate = AdaptiveFrameRate()
        rate.setDemand(row.demand)
        rate.setPowerConstrained(row.constrained)
        expectProcessed(&rate, 100)
        rate.record(face: true, at: 100)
        return rate
    }

    /// Asks whether the frame at `t` is processed (which counts it, so `#expect` cannot call `shouldProcess`
    /// directly: it is mutating) and checks the answer.
    private func expectProcessed(
        _ rate: inout AdaptiveFrameRate, _ t: TimeInterval, _ expected: Bool = true,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let processed = rate.shouldProcess(frameAt: t)
        #expect(processed == expected, sourceLocation: sourceLocation)
    }

    private func time(for row: Row) -> TimeInterval { row.faceRecent ? 101 : 105 }

    /// Feeds frames at `fps` for `seconds` from `start` and returns the times that were processed. Each processed
    /// frame is recorded with the face given by `face`.
    private func simulate(
        _ rate: inout AdaptiveFrameRate, from start: TimeInterval, seconds: Double, fps: Double,
        face: (TimeInterval) -> Bool = { _ in false }
    ) -> [TimeInterval] {
        var processed: [TimeInterval] = []
        for index in 0...Int((seconds * fps).rounded()) {
            let t = start + Double(index) / fps
            if rate.shouldProcess(frameAt: t) {
                rate.record(face: face(t), at: t)
                processed.append(t)
            }
        }
        return processed
    }

    private func gaps(_ times: [TimeInterval]) -> [TimeInterval] {
        zip(times, times.dropFirst()).map { $1 - $0 }
    }

    // MARK: Start and the table

    @Test("The first frame is always processed", arguments: table)
    func firstFrameIsAlwaysProcessed(row: Row) {
        var rate = AdaptiveFrameRate()
        rate.setDemand(row.demand)
        rate.setPowerConstrained(row.constrained)

        expectProcessed(&rate, 12_345.678)
    }

    @Test("Every row of the interval table", arguments: table)
    func intervalTable(row: Row) {
        let rate = makeRate(row)

        #expect(abs(rate.minimumInterval(at: time(for: row)) - row.interval) < epsilon)
    }

    @Test("Over 10 s of 60 fps input each row processes at its rate and no faster", arguments: table)
    func processedRatePerRow(row: Row) {
        var rate = makeRate(row)
        // Continue right after the first frame (its face keeps the face rows recent) or, for the absent rows, 5 s
        // after it, when the interval is already long over and the first frame is processed at once.
        let start: TimeInterval = row.faceRecent ? 100 : 105
        let processed = simulate(&rate, from: start, seconds: 10, fps: 60) { _ in row.faceRecent }

        // 60 fps input has 60 / 15 = 4, 6, 12, or 30 frames per interval, so every interval is a whole number of
        // frames. The face rows start at the frame just processed, so they count from the next interval.
        let framesPerInterval = (row.interval * 60).rounded()
        let expected = Int((600 / framesPerInterval).rounded(.down)) + (row.faceRecent ? 0 : 1)
        #expect(processed.count == expected)
        for gap in gaps(processed) {
            #expect(abs(gap - row.interval) < 1e-6)
        }
    }

    @Test func fullDemandIgnoresPowerAndFaces() {
        var rate = AdaptiveFrameRate()
        rate.setPowerConstrained(true)
        let processed = simulate(&rate, from: 0, seconds: 20, fps: 15)

        // 15 fps input with no face for 20 s and a power constraint: every frame is still processed.
        #expect(processed.count == 301)
    }

    // MARK: Boundaries and tolerance

    @Test(
        "A frame is processed from interval minus 4 ms after the last one, not before",
        arguments: table.filter { !$0.faceRecent })
    func toleranceBoundary(row: Row) {
        let interval = row.interval
        func prepared() -> AdaptiveFrameRate {
            var rate = AdaptiveFrameRate()
            rate.setDemand(row.demand)
            rate.setPowerConstrained(row.constrained)
            // For the adaptive rows, the face is gone long before the frames below.
            _ = rate.shouldProcess(frameAt: 0)
            rate.record(face: false, at: 0)
            _ = rate.shouldProcess(frameAt: 10)
            rate.record(face: false, at: 10)
            return rate
        }

        var justBefore = prepared()
        expectProcessed(&justBefore, 10 + interval - tolerance - 1e-6, false)
        var justAfter = prepared()
        expectProcessed(&justAfter, 10 + interval - tolerance + 1e-6)
    }

    @Test func aRejectedFrameDoesNotMoveTheInterval() {
        var rate = AdaptiveFrameRate()
        expectProcessed(&rate, 0)
        expectProcessed(&rate, 0.03, false)
        // Still measured from 0, not from the rejected frame at 0.03.
        expectProcessed(&rate, 0.0667)
    }

    @Test func aProcessedFrameMovesTheInterval() {
        var rate = AdaptiveFrameRate()
        expectProcessed(&rate, 0)
        expectProcessed(&rate, 0.0627)
        // 0.0627 is the new reference: 0.1 is only 0.0373 later.
        expectProcessed(&rate, 0.1, false)
        expectProcessed(&rate, 0.0627 + 0.0627)
    }

    @Test func aFrameWithTheSameTimestampIsDropped() {
        var rate = AdaptiveFrameRate()
        expectProcessed(&rate, 5)
        expectProcessed(&rate, 5, false)
    }

    @Test func a15FpsDeviceIsNotThinnedByTimestampJitter() {
        var rate = AdaptiveFrameRate()
        var processed = 0
        for index in 0..<300 {
            // Alternating plus and minus 1.5 ms: neighbouring gaps differ from 1/15 s by up to 3 ms.
            let jitter = index.isMultiple(of: 2) ? 0.0015 : -0.0015
            if rate.shouldProcess(frameAt: 50 + Double(index) / 15 + jitter) { processed += 1 }
        }

        #expect(processed == 300)
    }

    @Test("Input above 15 fps is capped at 15 fps", arguments: [20.0, 24.0, 30.0, 60.0, 120.0])
    func hardCapAt15Fps(deviceRate: Double) {
        var rate = AdaptiveFrameRate()
        let processed = simulate(&rate, from: 0, seconds: 10, fps: deviceRate)

        // At most 15 per second, plus the first frame: no 1-second window holds more than 15 processed frames.
        #expect(processed.count <= 151)
        for (index, time) in processed.enumerated() {
            let inWindow = processed[index...].prefix { $0 < time + 1 - 1e-6 }.count
            #expect(inWindow <= 15)
        }
    }

    @Test("Exact multiples of the frame period give 15 fps from 30 fps input")
    func thirtyFpsGivesFifteen() {
        var rate = AdaptiveFrameRate()
        let processed = simulate(&rate, from: 0, seconds: 10, fps: 30)

        #expect(processed.count == 151)
        for gap in gaps(processed) {
            #expect(abs(gap - 2.0 / 30) < 1e-6)
        }
    }

    // MARK: Backwards time

    @Test func aTimestampBeforeTheLastProcessedOneIsProcessedAndRestartsTheInterval() {
        var rate = AdaptiveFrameRate()
        expectProcessed(&rate, 100)
        expectProcessed(&rate, 99.9)
        // The interval now runs from 99.9.
        expectProcessed(&rate, 99.95, false)
        expectProcessed(&rate, 99.9 + 1.0 / 15)
    }

    @Test func aBackwardsJumpPullsAFutureFaceTimeBack() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 1000)
        rate.record(face: true, at: 1000)
        // The clock restarts at 10. Without pulling the face time back, 13 would still look like 2 s after a face.
        expectProcessed(&rate, 10)
        expectProcessed(&rate, 12.9)
        rate.record(face: false, at: 12.9)

        // 3 s after the (pulled back) face time, so the 1/5 s interval applies.
        expectProcessed(&rate, 13.0, false)
        expectProcessed(&rate, 13.1)
    }

    @Test func aBackwardsJumpKeepsAnOldFaceTime() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 10)
        rate.record(face: true, at: 10)
        expectProcessed(&rate, 100)
        rate.record(face: false, at: 100)
        // Backwards, but still long after the last face at 10.
        expectProcessed(&rate, 50)
        rate.record(face: false, at: 50)

        #expect(abs(rate.minimumInterval(at: 50.05) - 0.2) < epsilon)
    }

    // MARK: The 2 s absence boundary

    @Test func aFaceIsRecentUpToButNotIncludingTwoSeconds() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 100)
        rate.record(face: true, at: 100)

        // 101.9921875 and 102 are exact in binary, so the boundary is exact.
        #expect(abs(rate.minimumInterval(at: 101.9921875) - 1.0 / 15) < epsilon)
        #expect(abs(rate.minimumInterval(at: 102) - 1.0 / 5) < epsilon)
        #expect(abs(rate.minimumInterval(at: 150) - 1.0 / 5) < epsilon)
    }

    @Test func theRateDropsToFiveFpsOnlyAfterTwoSecondsWithoutAFace() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        // A face at 100, then 15 fps input without one.
        _ = rate.shouldProcess(frameAt: 100)
        rate.record(face: true, at: 100)
        let processed = simulate(&rate, from: 100 + 1.0 / 15, seconds: 6, fps: 15)

        let inFirstTwoSeconds = processed.filter { $0 < 101.9 }
        #expect(inFirstTwoSeconds.count == 28)  // every frame from 100.0667 to 101.8667
        let afterwards = processed.filter { $0 > 102.2 }
        for gap in gaps(afterwards) {
            #expect(abs(gap - 0.2) < 1e-6)
        }
        #expect(afterwards.count > 15)
    }

    @Test func aFrameWithoutAFaceNeverRefreshesTheFaceTime() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 100)
        rate.record(face: true, at: 100)
        for index in 1...20 {
            let t = 100 + Double(index) * 0.1
            if rate.shouldProcess(frameAt: t) { rate.record(face: false, at: t) }
        }

        // 2 s after the last real face, however many frames were processed since.
        #expect(abs(rate.minimumInterval(at: 102) - 1.0 / 5) < epsilon)
    }

    // MARK: Face return

    @Test(
        "A processed frame with a face makes the next frame eligible at the active interval", arguments: [false, true])
    func faceReturnsAtOnce(constrained: Bool) {
        let active = constrained ? 0.1 : 1.0 / 15
        func throttled() -> AdaptiveFrameRate {
            var rate = AdaptiveFrameRate()
            rate.setDemand(.adaptive)
            rate.setPowerConstrained(constrained)
            _ = rate.shouldProcess(frameAt: 100)
            rate.record(face: true, at: 100)
            // 20 s without a face, then the first processed frame after the face returns.
            _ = rate.shouldProcess(frameAt: 120)
            return rate
        }

        var withFace = throttled()
        withFace.record(face: true, at: 120)
        // The very next frame at the active interval is processed.
        expectProcessed(&withFace, 120 + active)

        var withoutFace = throttled()
        withoutFace.record(face: false, at: 120)
        // Still throttled: the same frame is dropped.
        expectProcessed(&withoutFace, 120 + active, false)
    }

    @Test func aReturningFaceGetsEveryFrameAgain() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        _ = simulate(&rate, from: 0, seconds: 10, fps: 15)  // a long absence
        let processed = simulate(&rate, from: 10 + 1.0 / 15, seconds: 3, fps: 15) { $0 >= 10.5 }

        // Frames are thinned until the first processed face frame, then every frame is processed.
        let firstFace = processed.first { $0 >= 10.5 }
        let faceFrames = processed.filter { $0 >= 10.5 }
        #expect(firstFace != nil)
        #expect(faceFrames.count >= 37)  // 39 frames from 10.5 on, the first processed one at most 3 frames late
        for gap in gaps(faceFrames) {
            #expect(abs(gap - 1.0 / 15) < 1e-6)
        }
    }

    // MARK: reset

    @Test func resetProcessesTheNextFrameAndForgetsOldTimes() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 100)
        rate.record(face: true, at: 100)
        rate.reset()

        // Earlier than the old frame and right after it: both are simply the first frame of a new run.
        expectProcessed(&rate, 100.001)
        expectProcessed(&rate, 100.002, false)
    }

    @Test func resetPutsTheDemandBackToFullAndKeepsThePowerState() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.reduced)
        rate.setPowerConstrained(true)
        rate.reset()

        #expect(rate.demand == .full)
        #expect(rate.isPowerConstrained)
        #expect(abs(rate.minimumInterval(at: 5) - 1.0 / 15) < epsilon)
    }

    @Test func aStartCountsAsAFaceJustSeen() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        // An old face at 100 must not leak into the new run.
        _ = rate.shouldProcess(frameAt: 100)
        rate.record(face: true, at: 100)
        rate.reset()
        rate.setDemand(.adaptive)

        expectProcessed(&rate, 500)
        rate.record(face: false, at: 500)
        #expect(abs(rate.minimumInterval(at: 501.9921875) - 1.0 / 15) < epsilon)
        #expect(abs(rate.minimumInterval(at: 502) - 1.0 / 5) < epsilon)
    }

    @Test func aResetRateEqualsAFreshOne() {
        var rate = AdaptiveFrameRate()
        #expect(rate == AdaptiveFrameRate())
        _ = rate.shouldProcess(frameAt: 3)
        rate.record(face: true, at: 3)
        rate.setDemand(.reduced)
        #expect(rate != AdaptiveFrameRate())

        rate.reset()
        #expect(rate == AdaptiveFrameRate())
    }

    // MARK: Changes in the middle of a stream

    @Test func raisingTheDemandTakesEffectOnTheNextFrame() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.reduced)
        expectProcessed(&rate, 100)
        expectProcessed(&rate, 100.07, false)

        // 0.01 s later, and measured from the same frame at 100: only the new demand lets it through.
        rate.setDemand(.full)
        expectProcessed(&rate, 100.08)
        expectProcessed(&rate, 100.08 + 1.0 / 15)
    }

    @Test func loweringTheDemandTakesEffectOnTheNextFrame() {
        var rate = AdaptiveFrameRate()
        expectProcessed(&rate, 100)
        expectProcessed(&rate, 100 + 1.0 / 15)

        rate.setDemand(.reduced)
        expectProcessed(&rate, 100 + 2.0 / 15, false)
        expectProcessed(&rate, 100 + 3.0 / 15 - 0.001, false)
        expectProcessed(&rate, 100 + 1.0 / 15 + 0.2)
    }

    @Test func adaptiveStartsAtFullRateBecauseTheStartCountsAsAFace() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        let processed = simulate(&rate, from: 0, seconds: 1.8, fps: 15)

        #expect(processed.count == 28)  // every frame of the first 1.8 s
    }

    @Test func powerStateChangesTakeEffectOnTheNextFrame() {
        var rate = AdaptiveFrameRate()
        rate.setDemand(.adaptive)
        expectProcessed(&rate, 100)
        rate.record(face: true, at: 100)
        expectProcessed(&rate, 100 + 1.0 / 15)
        rate.record(face: true, at: 100 + 1.0 / 15)

        rate.setPowerConstrained(true)
        expectProcessed(&rate, 100 + 2.0 / 15, false)  // 1/15 s after the last: not yet 1/10 s
        expectProcessed(&rate, 100 + 3.0 / 15)  // 2/15 s after the last
        rate.record(face: true, at: 100 + 3.0 / 15)

        rate.setPowerConstrained(false)
        expectProcessed(&rate, 100 + 4.0 / 15)
    }

    @Test func aThrottledSourceStillProcessesAFrameAtLeastEveryIntervalPlusOneDeviceFrame() {
        for (constrained, interval) in [(false, 0.2), (true, 0.5)] {
            var rate = AdaptiveFrameRate()
            rate.setDemand(.adaptive)
            rate.setPowerConstrained(constrained)
            let processed = simulate(&rate, from: 0, seconds: 60, fps: 15).filter { $0 > 3 }

            #expect(processed.count > 20)
            for gap in gaps(processed) {
                #expect(gap >= interval - tolerance - 1e-6)
                #expect(gap <= interval + 1.0 / 15 + 1e-6)
            }
        }
    }
}
