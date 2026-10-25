import CoreMedia
import SwayModels
import Testing

@testable import CameraService

@Suite("Frame rate clamping")
struct FrameRateClamperTests {
    private let typical = [FrameRateRange(min: 1, max: 30)]

    @Test func rateInsideARangeIsKept() {
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: typical) == 15)
        #expect(FrameRateClamper.clampedFrameRate(requested: 30, ranges: typical) == 30)
        #expect(FrameRateClamper.clampedFrameRate(requested: 1, ranges: typical) == 1)
    }

    @Test func rateAboveTheRangeClampsToItsMaximum() {
        #expect(FrameRateClamper.clampedFrameRate(requested: 60, ranges: typical) == 30)
    }

    @Test func rateBelowTheRangeClampsToItsMinimum() {
        let fixed = [FrameRateRange(min: 24, max: 30)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: fixed) == 24)
    }

    @Test func requestBetweenTwoRangesGoesToTheNearestBoundary() {
        let ranges = [FrameRateRange(min: 5, max: 10), FrameRateRange(min: 30, max: 60)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 12, ranges: ranges) == 10)
        #expect(FrameRateClamper.clampedFrameRate(requested: 25, ranges: ranges) == 30)
    }

    @Test func requestInsideALaterRangeIsKept() {
        let ranges = [FrameRateRange(min: 5, max: 10), FrameRateRange(min: 12, max: 20)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: ranges) == 15)
    }

    @Test func equalDistanceGoesToTheEarlierRange() {
        let ranges = [FrameRateRange(min: 1, max: 10), FrameRateRange(min: 20, max: 30)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: ranges) == 10)
    }

    @Test func noRangesMeansLeaveTheDeviceAlone() {
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: []) == nil)
    }

    @Test func invalidRangesAreIgnored() {
        let ranges = [
            FrameRateRange(min: 30, max: 10),
            FrameRateRange(min: 0, max: 30),
            FrameRateRange(min: .nan, max: 30),
        ]
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: ranges) == nil)
        let withGoodOne = ranges + [FrameRateRange(min: 1, max: 30)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 15, ranges: withGoodOne) == 15)
    }

    @Test(arguments: [0.0, -5.0, Double.nan, Double.infinity])
    func invalidRequestFallsBackToTheDefaultRate(requested: Double) {
        #expect(FrameRateClamper.clampedFrameRate(requested: requested, ranges: typical) == SwayPolicy.defaultFrameRate)
    }

    @Test func boundaryNoiseCountsAsInsideTheRange() {
        let ranges = [FrameRateRange(min: 1, max: 29.97)]
        #expect(FrameRateClamper.clampedFrameRate(requested: 29.97 + 1e-9, ranges: ranges) == 29.97 + 1e-9)
    }

    @Test func frameDurationIsOneOverTheRate() {
        let duration = FrameRateClamper.frameDuration(forRate: 15)
        #expect(duration.seconds == 1.0 / 15.0)
        #expect(duration.isValid)
        let thirty = FrameRateClamper.frameDuration(forRate: 30)
        #expect(abs(thirty.seconds - 1.0 / 30.0) < 1e-12)
    }

    @Test func frameDurationHandlesFractionalRates() {
        let duration = FrameRateClamper.frameDuration(forRate: 29.97)
        #expect(abs(duration.seconds - 1.0 / 29.97) < 1e-5)
    }
}
