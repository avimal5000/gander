import Foundation
import GanderModels
import Testing

@testable import SwitchEngine

@Suite struct ProfileFitterTests {
    private let engine = PoseSwitchEngine()
    private let a: DisplayID = "A"
    private let b: DisplayID = "B"
    private let c: DisplayID = "C"

    private func fit(
        _ segments: [TraceSegment],
        layout: DisplayLayout? = nil,
        features: PoseFeatureSet = .visionAngles,
        rounds: Set<Int>? = nil
    ) throws -> CalibrationProfile {
        try engine.fitProfile(
            from: TraceFactory.trace(segments, layout: layout), features: features, rounds: rounds)
    }

    // MARK: Means and standard deviations

    @Test func meansAndSampleStandardDeviationsAreExact() throws {
        // 40 alternating samples: mean = center, std = spread * sqrt(40 / 39) (n - 1 denominator).
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 10, yawSpread: 3, pitch: 5, pitchSpread: 2),
            TraceFactory.segment(b, count: 50, yaw: -20, yawSpread: 1, pitch: 12, pitchSpread: 4),
        ])
        let first = try #require(profile.profile(for: a))
        let second = try #require(profile.profile(for: b))
        #expect(abs(first.yaw - 10) < 1e-12)
        #expect(abs(first.pitch - 5) < 1e-12)
        #expect(abs(first.yawStd - 3 * (40.0 / 39.0).squareRoot()) < 1e-12)
        #expect(abs(first.pitchStd - 2 * (40.0 / 39.0).squareRoot()) < 1e-12)
        #expect(first.sampleCount == 40)
        #expect(abs(second.yaw + 20) < 1e-12)
        #expect(abs(second.pitch - 12) < 1e-12)
        #expect(abs(second.yawStd - (50.0 / 49.0).squareRoot()) < 1e-12)
        #expect(abs(second.pitchStd - 4 * (50.0 / 49.0).squareRoot()) < 1e-12)
        #expect(second.sampleCount == 50)
    }

    @Test func segmentsOfSeveralRoundsForOneDisplayArePooled() throws {
        let profile = try fit([
            TraceFactory.segment(a, round: 1, count: 20, yaw: 10, pitch: 0),
            TraceFactory.segment(b, round: 1, count: 40, yaw: 30, pitch: 0),
            TraceFactory.segment(a, round: 2, count: 20, yaw: 20, pitch: 0),
        ])
        let pooled = try #require(profile.profile(for: a))
        #expect(pooled.sampleCount == 40)
        #expect(abs(pooled.yaw - 15) < 1e-12)
    }

    @Test func landmarkFeaturesUseLandmarkAngles() throws {
        let segments = [
            TraceFactory.segment(a, count: 40, yaw: 10, pitch: 5),
            TraceFactory.segment(b, count: 40, yaw: 30, pitch: 7),
        ]
        let profile = try fit(segments, features: .landmarkAngles)
        #expect(profile.features == .landmarkAngles)
        let first = try #require(profile.profile(for: a))
        // The factory sets landmark angles to 0.9 * the Vision angles.
        #expect(abs(first.yaw - 9) < 1e-12)
        #expect(abs(first.pitch - 4.5) < 1e-12)
    }

    // MARK: Scales

    @Test func scalesPoolTheStandardDeviationsAsRootMeanSquare() throws {
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 0, yawSpread: 3, pitch: 0, pitchSpread: 6),
            TraceFactory.segment(b, count: 40, yaw: 30, yawSpread: 5, pitch: 0, pitchSpread: 8),
        ])
        let expectedYaw = ((9 + 25) / 2.0 * (40.0 / 39.0)).squareRoot()
        let expectedPitch = ((36 + 64) / 2.0 * (40.0 / 39.0)).squareRoot()
        #expect(abs(profile.yawScale - expectedYaw) < 1e-12)
        #expect(abs(profile.pitchScale - expectedPitch) < 1e-12)
    }

    @Test func scalesAreFlooredWhenTheCalibrationIsVeryStill() throws {
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 0, yawSpread: 0.1, pitch: 0, pitchSpread: 0.1),
            TraceFactory.segment(b, count: 40, yaw: 30, yawSpread: 0.1, pitch: 0, pitchSpread: 0.1),
        ])
        #expect(profile.yawScale == 1.5)
        #expect(profile.pitchScale == 2.5)
    }

    @Test func pitchScaleNeverFallsBelowYawScale() throws {
        // Yaw spread 4 (yawScale about 4.05) with tiny pitch spread: pitchScale is lifted to yawScale.
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 0, yawSpread: 4, pitch: 0, pitchSpread: 1),
            TraceFactory.segment(b, count: 40, yaw: 30, yawSpread: 4, pitch: 0, pitchSpread: 1),
        ])
        #expect(profile.yawScale > 4)
        #expect(profile.pitchScale == profile.yawScale)
    }

    @Test func pitchScaleCanExceedYawScale() throws {
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 0, yawSpread: 1, pitch: 0, pitchSpread: 6),
            TraceFactory.segment(b, count: 40, yaw: 30, yawSpread: 1, pitch: 0, pitchSpread: 6),
        ])
        #expect(profile.yawScale == 1.5)
        #expect(profile.pitchScale > 6)
    }

    // MARK: Which displays and samples count

    @Test func displayWithFewerThanThirtyPointsIsDropped() throws {
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
            TraceFactory.segment(b, count: 29, yaw: 20, pitch: 0),
            TraceFactory.segment(c, count: 40, yaw: 30, pitch: 0),
        ])
        #expect(profile.displays.map(\.displayID) == [a, c])
    }

    @Test func displayWithExactlyThirtyPointsIsKept() throws {
        let profile = try fit([
            TraceFactory.segment(a, count: 30, yaw: 10, pitch: 0),
            TraceFactory.segment(b, count: 30, yaw: 20, pitch: 0),
        ])
        #expect(profile.displays.map(\.displayID) == [a, b])
    }

    @Test func framesWithoutAFaceDoNotCountTowardsThePointMinimum() throws {
        let mixed = TraceSegment(
            displayID: b,
            round: 1,
            samples: TraceFactory.segment(b, count: 29, yaw: 20, pitch: 0).samples
                + TraceFactory.emptySegment(b, count: 30).samples
        )
        let profile = try fit([
            TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
            mixed,
            TraceFactory.segment(c, count: 40, yaw: 30, pitch: 0),
        ])
        #expect(profile.displays.map(\.displayID) == [a, c])
    }

    @Test func unlabeledSegmentsAreIgnored() throws {
        let profile = try fit([
            TraceFactory.segment(nil, round: 0, count: 100, yaw: 99, pitch: 99),
            TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
            TraceFactory.segment(b, count: 40, yaw: 20, pitch: 0),
        ])
        #expect(profile.displays.map(\.displayID) == [a, b])
        #expect(profile.displays.allSatisfy { $0.yaw < 50 })
    }

    @Test func unlabeledSegmentsAreNotUsed() {
        let trace = TraceFactory.trace([
            TraceFactory.segment(nil, round: 0, count: 100, yaw: 10, pitch: 0),
            TraceFactory.emptySegment(a, count: 40),
        ])
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
        }
    }

    @Test func roundsFilterSelectsOnlyThoseRounds() throws {
        let segments = [
            TraceFactory.segment(a, round: 1, count: 40, yaw: 10, pitch: 0),
            TraceFactory.segment(b, round: 1, count: 40, yaw: 30, pitch: 0),
            TraceFactory.segment(a, round: 2, count: 40, yaw: 14, pitch: 0),
            TraceFactory.segment(b, round: 2, count: 40, yaw: 36, pitch: 0),
        ]
        let first = try fit(segments, rounds: [1])
        let second = try fit(segments, rounds: [2])
        let both = try fit(segments, rounds: [1, 2])
        let all = try fit(segments, rounds: nil)
        #expect(abs(try #require(first.profile(for: a)).yaw - 10) < 1e-12)
        #expect(abs(try #require(first.profile(for: b)).yaw - 30) < 1e-12)
        #expect(abs(try #require(second.profile(for: a)).yaw - 14) < 1e-12)
        #expect(abs(try #require(second.profile(for: b)).yaw - 36) < 1e-12)
        #expect(abs(try #require(all.profile(for: a)).yaw - 12) < 1e-12)
        #expect(both == all)
        #expect(first.displays.allSatisfy { $0.sampleCount == 40 })
        #expect(all.displays.allSatisfy { $0.sampleCount == 80 })
    }

    @Test func roundsFilterThatSelectsNothingIsTooFewDisplays() {
        let trace = TraceFactory.trace([
            TraceFactory.segment(a, round: 1, count: 40, yaw: 10, pitch: 0),
            TraceFactory.segment(b, round: 1, count: 40, yaw: 30, pitch: 0),
        ])
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: trace, features: .visionAngles, rounds: [5])
        }
    }

    // MARK: Errors

    @Test func landmarksMissingFromTheTraceReportMissingFeatures() {
        let noLandmarks = [a, b].map { id in
            TraceSegment(
                displayID: id,
                round: 1,
                samples: (0..<40).map { PoseSample(timestamp: Double($0) / 15, pose: makePose(yaw: 10, pitch: 0)) }
            )
        }
        let trace = TraceFactory.trace(noLandmarks)
        #expect(throws: CalibrationError.featuresMissing(.landmarkAngles)) {
            try engine.fitProfile(from: trace, features: .landmarkAngles, rounds: nil)
        }
    }

    @Test func aPoseWithOnlyOneLandmarkAngleDoesNotHaveTheFeatures() {
        let halfLandmarks = [a, b].map { id in
            TraceSegment(
                displayID: id,
                round: 1,
                samples: (0..<40).map {
                    PoseSample(timestamp: Double($0) / 15, pose: makePose(yaw: 10, pitch: 0, landmarkYaw: 3))
                }
            )
        }
        let trace = TraceFactory.trace(halfLandmarks)
        #expect(throws: CalibrationError.featuresMissing(.landmarkAngles)) {
            try engine.fitProfile(from: trace, features: .landmarkAngles, rounds: nil)
        }
    }

    /// No faces at all (camera covered) is too little data, not missing features: every face has Vision angles.
    @Test func aTraceWithNoFacesOrNoSegmentsIsTooFewDisplays() {
        let noFaces = TraceFactory.trace([
            TraceFactory.emptySegment(a, count: 50), TraceFactory.emptySegment(b, count: 50),
        ])
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: noFaces, features: .visionAngles, rounds: nil)
        }
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: TraceFactory.trace([]), features: .visionAngles, rounds: nil)
        }
    }

    @Test func oneUsableDisplayIsTooFew() {
        let trace = TraceFactory.trace([
            TraceFactory.segment(a, count: 100, yaw: 10, pitch: 0),
            TraceFactory.segment(b, count: 29, yaw: 30, pitch: 0),
        ])
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
        }
    }

    @Test func twoDisplaysThatAreEachJustUnderTheMinimumAreTooFew() {
        let trace = TraceFactory.trace([
            TraceFactory.segment(a, count: 29, yaw: 10, pitch: 0),
            TraceFactory.segment(b, count: 29, yaw: 30, pitch: 0),
        ])
        #expect(throws: CalibrationError.tooFewDisplays) {
            try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
        }
    }

    // MARK: Ordering and bookkeeping

    @Test func displaysFollowTheLayoutOrderNotTheSegmentOrder() throws {
        let layout = makeLayout([c, b, a])
        let profile = try fit(
            [
                TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
                TraceFactory.segment(b, count: 40, yaw: 20, pitch: 0),
                TraceFactory.segment(c, count: 40, yaw: 30, pitch: 0),
            ],
            layout: layout
        )
        #expect(profile.displays.map(\.displayID) == layout.displays.map(\.id))
        #expect(profile.displays.map(\.displayID) == [c, b, a])
    }

    @Test func displaysMissingFromTheLayoutFollowInOrderOfFirstAppearance() throws {
        let extra1: DisplayID = "X"
        let extra2: DisplayID = "Y"
        let layout = makeLayout([b, a, c])  // c has no segment: ignored
        let profile = try fit(
            [
                TraceFactory.segment(extra1, count: 40, yaw: 1, pitch: 0),
                TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
                TraceFactory.segment(extra2, count: 40, yaw: 2, pitch: 0),
                TraceFactory.segment(b, count: 40, yaw: 20, pitch: 0),
            ],
            layout: layout
        )
        #expect(profile.displays.map(\.displayID) == [b, a, extra1, extra2])
    }

    @Test func aTraceWithoutALayoutKeepsFirstAppearanceOrderAndAnEmptyFingerprint() throws {
        let profile = try fit([
            TraceFactory.segment(b, count: 40, yaw: 20, pitch: 0),
            TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
        ])
        #expect(profile.displays.map(\.displayID) == [b, a])
        #expect(profile.layoutFingerprint == "")
    }

    @Test func bookkeepingFieldsComeFromTheTraceAndTheCall() throws {
        let layout = makeLayout([a, b])
        let profile = try fit(
            [
                TraceFactory.segment(a, count: 40, yaw: 10, pitch: 0),
                TraceFactory.segment(b, count: 40, yaw: 20, pitch: 0),
            ],
            layout: layout,
            features: .landmarkAngles
        )
        #expect(profile.layoutFingerprint == layout.fingerprint)
        #expect(profile.cameraName == "Test camera")
        #expect(profile.createdAt == TraceFactory.createdAt)
        #expect(profile.features == .landmarkAngles)
        #expect(profile.formatVersion == CalibrationProfile.currentFormatVersion)
        #expect(profile.matches(layout))
    }

    @Test func fittingIsDeterministic() throws {
        var rng = SplitMix64(seed: 99)
        let segments = [a, b, c].enumerated().map { index, id in
            let samples = (0..<60).map { frame in
                PoseSample(
                    timestamp: Double(frame) / 15,
                    pose: makePose(
                        yaw: Double(index) * 20 + rng.nextGaussian() * 1.5, pitch: 5 + rng.nextGaussian() * 2.5)
                )
            }
            return TraceSegment(displayID: id, round: 1, samples: samples)
        }
        let layout = makeLayout([a, b, c])
        let first = try fit(segments, layout: layout)
        let second = try fit(segments, layout: layout)
        #expect(first == second)
    }
}
