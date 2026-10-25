import Foundation
import SwayModels
import Testing

@testable import SwitchEngine

@Suite struct PoseClassifierTests {
    private let engine = PoseSwitchEngine()
    private let d1: DisplayID = "D1"
    private let d2: DisplayID = "D2"
    private let d3: DisplayID = "D3"
    private let settings = SwitchSettings.default  // elsewhere margins 20 (yaw) / 15 (pitch), min confidence 0.5

    /// D1 at (0, 0) and D2 at (10, 0); `yawScale` 2, `pitchScale` 4. Elsewhere box under the default settings:
    /// yaw -20...30, pitch -15...15.
    private func profile(
        features: PoseFeatureSet = .visionAngles,
        displays: [(DisplayID, Double, Double)]? = nil,
        yawScale: Double = 2,
        pitchScale: Double = 4
    ) -> CalibrationProfile {
        let centers = displays ?? [(d1, 0, 0), (d2, 10, 0)]
        return CalibrationProfile(
            features: features,
            displays: centers.map {
                DisplayProfile(displayID: $0.0, yaw: $0.1, pitch: $0.2, yawStd: 1, pitchStd: 1, sampleCount: 50)
            },
            yawScale: yawScale,
            pitchScale: pitchScale,
            layoutFingerprint: "test",
            cameraName: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func classify(
        _ pose: HeadPose?,
        with profile: CalibrationProfile? = nil,
        settings: SwitchSettings? = nil
    ) -> PoseClassification {
        engine.classify(pose, with: profile ?? self.profile(), settings: settings ?? self.settings)
    }

    // MARK: Nearest display and margin

    @Test func nearestDisplayWinsWithAHandComputedMargin() throws {
        // Pose (2, 4): d1 = sqrt((2/2)^2 + (4/4)^2) = sqrt(2); d2 = sqrt((8/2)^2 + (4/4)^2) = sqrt(17).
        let result = classify(makePose(yaw: 2, pitch: 4))
        let near = 2.0.squareRoot()
        let far = 17.0.squareRoot()
        #expect(result.kind == .display)
        #expect(result.best == d1)
        #expect(result.runnerUp == d2)
        #expect(abs(result.margin - (far - near) / (far + near)) < 1e-12)
        #expect(abs(try #require(result.distances[d1]) - near) < 1e-12)
        #expect(abs(try #require(result.distances[d2]) - far) < 1e-12)
        #expect(result.distances.count == 2)
    }

    @Test func aPoseAtADisplayCenterHasMarginOne() {
        let result = classify(makePose(yaw: 10, pitch: 0))
        #expect(result.best == d2)
        #expect(result.runnerUp == d1)
        #expect(result.margin == 1)
        #expect(result.distances[d2] == 0)
    }

    @Test func marginIsZeroHalfwayBetweenTwoDisplaysAndTiesGoToTheEarlierDisplay() throws {
        let result = classify(makePose(yaw: 5, pitch: 0))
        #expect(result.kind == .display)
        #expect(result.best == d1)
        #expect(result.runnerUp == d2)
        #expect(result.margin == 0)

        let reversed = profile(displays: [(d2, 10, 0), (d1, 0, 0)])
        let flipped = classify(makePose(yaw: 5, pitch: 0), with: reversed)
        #expect(flipped.best == d2)
        #expect(flipped.runnerUp == d1)
    }

    @Test func whenEveryDistanceIsZeroTheMarginIsZeroNotNaN() {
        let stacked = profile(displays: [(d1, 3, 3), (d2, 3, 3)])
        let result = classify(makePose(yaw: 3, pitch: 3), with: stacked)
        #expect(result.kind == .display)
        #expect(result.best == d1)
        #expect(result.runnerUp == d2)
        #expect(result.margin == 0)
    }

    @Test func runnerUpIsTheSecondNearestAmongThree() {
        let three = profile(displays: [(d1, 0, 0), (d2, 10, 0), (d3, 40, 0)])
        let result = classify(makePose(yaw: 14, pitch: 0), with: three)
        #expect(result.best == d2)
        #expect(result.runnerUp == d1)
        #expect(result.distances.count == 3)
        #expect(result.distances[d3] == 13)
    }

    @Test func thirdPlaceTiesDoNotDisturbBestAndRunnerUp() {
        // Equal distances 5 / 5 for D2 and D3 behind a nearer D1: the earlier of the tied pair is the runner-up.
        let three = profile(displays: [(d1, 5, 0), (d2, 0, 0), (d3, 10, 0)])
        let result = classify(makePose(yaw: 5, pitch: 0), with: three)
        #expect(result.best == d1)
        #expect(result.runnerUp == d2)
        #expect(result.margin == 1)
    }

    // MARK: Axis scales

    @Test func theSameAngularOffsetCountsLessInPitchThanInYaw() throws {
        // yawScale 2, pitchScale 4: 4 degrees is 2 scale units in yaw but only 1 in pitch.
        let yawOffset = classify(makePose(yaw: 4, pitch: 0))
        let pitchOffset = classify(makePose(yaw: 0, pitch: 4))
        #expect(yawOffset.distances[d1] == 2)
        #expect(pitchOffset.distances[d1] == 1)
        #expect(try #require(pitchOffset.distances[d1]) < #require(yawOffset.distances[d1]))
    }

    // MARK: Elsewhere

    @Test(arguments: [
        (-20.5, 0.0),  // left of the lowest yaw (0 - 20)
        (30.5, 0.0),  // right of the highest yaw (10 + 20)
        (5.0, -15.5),  // below the lowest pitch (0 - 15)
        (5.0, 15.5),  // above the highest pitch (0 + 15)
        (100.0, 100.0),  // far off in both
    ])
    func posesOutsideTheBoxAreElsewhere(yaw: Double, pitch: Double) {
        let result = classify(makePose(yaw: yaw, pitch: pitch))
        #expect(result.kind == .elsewhere)
        #expect(result.margin == 0)
    }

    @Test(arguments: [
        (-20.0, 0.0), (30.0, 0.0), (5.0, -15.0), (5.0, 15.0),
    ])
    func posesOnTheBoxEdgeAreStillDisplays(yaw: Double, pitch: Double) {
        #expect(classify(makePose(yaw: yaw, pitch: pitch)).kind == .display)
    }

    @Test func elsewhereKeepsBestRunnerUpAndDistances() {
        let result = classify(makePose(yaw: -25, pitch: 0))
        #expect(result.kind == .elsewhere)
        #expect(result.best == d1)
        #expect(result.runnerUp == d2)
        #expect(result.margin == 0)
        #expect(result.distances[d1] == 12.5)
        #expect(result.distances[d2] == 17.5)
    }

    @Test func theElsewhereBoxFollowsTheSettingsMargins() {
        var tight = settings
        tight.elsewhereYawMargin = 5
        tight.elsewherePitchMargin = 2
        #expect(classify(makePose(yaw: 16, pitch: 0), settings: tight).kind == .elsewhere)
        #expect(classify(makePose(yaw: 15, pitch: 0), settings: tight).kind == .display)
        #expect(classify(makePose(yaw: 5, pitch: 3), settings: tight).kind == .elsewhere)
        #expect(classify(makePose(yaw: 5, pitch: 2), settings: tight).kind == .display)
    }

    // MARK: No face

    @Test func noPoseIsNoFace() {
        #expect(classify(nil) == .noFace)
        #expect(classify(nil).best == nil)
        #expect(classify(nil).distances.isEmpty)
    }

    @Test func confidenceBelowTheMinimumIsNoFace() {
        #expect(classify(makePose(yaw: 0, pitch: 0, confidence: 0.49)) == .noFace)
        #expect(classify(makePose(yaw: 0, pitch: 0, confidence: 0.5)).kind == .display)
    }

    @Test func theMinimumConfidenceComesFromTheSettings() {
        var strict = settings
        strict.minFaceConfidence = 0.9
        #expect(classify(makePose(yaw: 0, pitch: 0, confidence: 0.8), settings: strict) == .noFace)
        #expect(classify(makePose(yaw: 0, pitch: 0, confidence: 0.8)).kind == .display)
    }

    @Test(
        arguments: [
            (nil, nil), (3.0, nil), (nil, 4.0),
        ] as [(Double?, Double?)])
    func aLandmarkProfileTreatsMissingLandmarksAsNoFace(landmarkYaw: Double?, landmarkPitch: Double?) {
        let landmarkProfile = profile(features: .landmarkAngles)
        let pose = makePose(yaw: 0, pitch: 0, landmarkYaw: landmarkYaw, landmarkPitch: landmarkPitch)
        #expect(classify(pose, with: landmarkProfile) == .noFace)
    }

    @Test func aLandmarkProfileClassifiesOnLandmarkAnglesNotVisionAngles() {
        let landmarkProfile = profile(features: .landmarkAngles)
        // Vision angles are far outside, but the landmark angles are the ones used.
        let pose = makePose(yaw: 99, pitch: 99, landmarkYaw: 2, landmarkPitch: 4)
        let result = classify(pose, with: landmarkProfile)
        #expect(result == classify(makePose(yaw: 2, pitch: 4)))
        #expect(result.kind == .display)
        #expect(result.best == d1)
    }

    @Test func aVisionProfileIgnoresLandmarkAngles() {
        let pose = makePose(yaw: 2, pitch: 4, landmarkYaw: 99, landmarkPitch: 99)
        #expect(classify(pose) == classify(makePose(yaw: 2, pitch: 4)))
    }

    // MARK: Profiles the fitter never produces

    @Test func aProfileWithoutDisplaysAlwaysGivesNoFace() {
        let empty = profile(displays: [])
        #expect(classify(makePose(yaw: 0, pitch: 0), with: empty) == .noFace)
    }

    @Test func aSingleDisplayHasNoRunnerUpAndNeverAConfidentMargin() {
        let single = profile(displays: [(d1, 0, 0)])
        let result = classify(makePose(yaw: 1, pitch: 0), with: single)
        #expect(result.kind == .display)
        #expect(result.best == d1)
        #expect(result.runnerUp == nil)
        #expect(result.margin == 0)
        #expect(result.distances.count == 1)
    }
}
