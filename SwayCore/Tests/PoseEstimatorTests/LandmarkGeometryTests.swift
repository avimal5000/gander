import CoreGraphics
import Foundation
import Testing

@testable import PoseEstimator

@Suite("LandmarkGeometry")
struct LandmarkGeometryTests {
    private let noseDrop = LandmarkGeometry.noseDrop
    private let noseProtrusion = LandmarkGeometry.noseProtrusion

    /// An eye-region outline around `center` in model space: eight points on a small ellipse, like Vision's eye
    /// contour. Its centroid is exactly `center`.
    private func eyeOutline(around center: (x: Double, y: Double)) -> [(x: Double, y: Double)] {
        (0..<8).map { index in
            let angle = Double(index) * .pi / 4
            return (x: center.x + 0.15 * cos(angle), y: center.y + 0.06 * sin(angle))
        }
    }

    /// Landmarks of a head turned by the given angles, rolled, then placed in the face box.
    ///
    /// The head model matches the documented one: eye centers one inter-ocular distance (`scale`) apart, the nose
    /// tip `noseDrop` below and `noseProtrusion` in front of the eye midpoint. Pitch is applied first, then yaw.
    /// `pitchUpDegrees` is the head tilted up; `yawDegrees` is positive toward image-right. Each eye is given as an
    /// outline whose centroid is the eye center.
    private func points(
        yawDegrees: Double = 0,
        pitchUpDegrees: Double = 0,
        rollDegrees: Double = 0,
        scale: Double = 0.3,
        center: CGPoint = CGPoint(x: 0.5, y: 0.6),
        aspect: Double = 1
    ) -> LandmarkGeometry.Points {
        let yaw = yawDegrees * .pi / 180
        let pitch = pitchUpDegrees * .pi / 180
        let roll = rollDegrees * .pi / 180

        // Model space: x right, y up, z toward the camera, units of inter-ocular distance.
        let eyeA = (x: -0.5 * cos(yaw), y: 0.0)
        let eyeB = (x: 0.5 * cos(yaw), y: 0.0)
        let noseY = -noseDrop * cos(pitch) + noseProtrusion * sin(pitch)
        let noseZ = noseDrop * sin(pitch) + noseProtrusion * cos(pitch)
        let nose = (x: noseZ * sin(yaw), y: noseY)

        func place(_ point: (x: Double, y: Double)) -> CGPoint {
            // Roll in the image plane, then scale into the face box (x compensated for the box aspect).
            let rx = point.x * cos(roll) - point.y * sin(roll)
            let ry = point.x * sin(roll) + point.y * cos(roll)
            return CGPoint(x: center.x + rx * scale / aspect, y: center.y + ry * scale)
        }
        return LandmarkGeometry.Points(
            leftEyeRegion: eyeOutline(around: eyeA).map(place),
            rightEyeRegion: eyeOutline(around: eyeB).map(place),
            noseRegion: [place(nose)]
        )
    }

    private func center(_ region: [CGPoint]) throws -> CGPoint {
        try #require(LandmarkGeometry.eyeCenter(region: region))
    }

    private func angles(_ points: LandmarkGeometry.Points, aspect: Double = 1) throws -> LandmarkGeometry.Angles {
        try #require(LandmarkGeometry.angles(from: points, boxAspect: aspect))
    }

    // MARK: Frontal

    @Test func frontalFaceIsAboutZero() throws {
        let result = try angles(points())
        #expect(abs(result.yaw) < 1e-9)
        #expect(abs(result.pitch) < 1e-9)
    }

    @Test func frontalFaceIsZeroWhateverTheFaceScaleOrPosition() throws {
        for scale in [0.15, 0.3, 0.45] {
            for center in [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.55, y: 0.7)] {
                let result = try angles(points(scale: scale, center: center))
                #expect(abs(result.yaw) < 1e-9)
                #expect(abs(result.pitch) < 1e-9)
            }
        }
    }

    // MARK: Round trips (exact while the nose is within 0.9 of its farthest drop, tilt up of about -11 degrees or more)

    @Test(arguments: [-60.0, -30, -10, 0, 10, 30, 60])
    func yawIsRecoveredFromTheHeadModel(yaw: Double) throws {
        let result = try angles(points(yawDegrees: yaw))
        #expect(abs(result.yaw - yaw) < 1e-6)
        #expect(abs(result.pitch) < 1e-6)
    }

    @Test(arguments: [-10.0, 0, 15, 30, 45])
    func pitchIsRecoveredFromTheHeadModelAsNoddingDownPositive(tiltUp: Double) throws {
        let result = try angles(points(pitchUpDegrees: tiltUp))
        #expect(abs(result.pitch - (-tiltUp)) < 1e-6)
        #expect(abs(result.yaw) < 1e-6)
    }

    @Test(arguments: [-45.0, -20, 0, 20, 45], [-10.0, 0, 10, 25, 40])
    func yawAndPitchTogetherAreRecoveredFromTheHeadModel(yaw: Double, tiltUp: Double) throws {
        let result = try angles(points(yawDegrees: yaw, pitchUpDegrees: tiltUp))
        #expect(abs(result.yaw - yaw) < 1e-6)
        #expect(abs(result.pitch - (-tiltUp)) < 1e-6)
    }

    // MARK: Monotonic and continuous

    @Test(arguments: [-20.0, 0, 25])
    func yawIncreasesStrictlyAsTheNoseMovesTowardImageRight(tiltUp: Double) throws {
        let values = try stride(from: -70.0, through: 70.0, by: 5.0).map {
            try angles(points(yawDegrees: $0, pitchUpDegrees: tiltUp)).yaw
        }
        for (previous, next) in zip(values, values.dropFirst()) {
            #expect(next > previous)
            #expect(next - previous < 10)  // continuous: no jump beyond what the 5 degree step allows
        }
        #expect(values.first.map { $0 < 0 } == true)
        #expect(values.last.map { $0 > 0 } == true)
    }

    @Test(arguments: [-30.0, 0, 30])
    func pitchDecreasesStrictlyAsTheHeadTiltsUp(yaw: Double) throws {
        // Positive pitch is nodding down (Vision's convention), so tilting up lowers it.
        let values = try stride(from: -30.0, through: 60.0, by: 5.0).map {
            try angles(points(yawDegrees: yaw, pitchUpDegrees: $0)).pitch
        }
        for (previous, next) in zip(values, values.dropFirst()) {
            #expect(next < previous)
            #expect(previous - next < 10)
        }
    }

    @Test func rawNoseOffsetsAreMonotonicInBothAxes() throws {
        // Directly over nose positions, independent of the head model's parameterization.
        let base = points()
        let tip = base.noseRegion[0]
        for dy in [-0.05, 0, 0.05] {
            let yaws = try stride(from: -0.3, through: 0.3, by: 0.02).map { dx -> Double in
                var moved = base
                moved.noseRegion = [CGPoint(x: tip.x + dx, y: tip.y + dy)]
                return try angles(moved).yaw
            }
            for (previous, next) in zip(yaws, yaws.dropFirst()) { #expect(next > previous) }
        }
        for dx in [-0.1, 0, 0.1] {
            let pitches = try stride(from: -0.15, through: 0.15, by: 0.01).map { dy -> Double in
                var moved = base
                moved.noseRegion = [CGPoint(x: tip.x + dx, y: tip.y + dy)]
                return try angles(moved).pitch
            }
            for (previous, next) in zip(pitches, pitches.dropFirst()) { #expect(next < previous) }
        }
    }

    @Test func noseMovingDownTheFaceRaisesPitchAndLeavesYawAtZero() throws {
        let base = points()
        var lower = base
        lower.noseRegion = [CGPoint(x: base.noseRegion[0].x, y: base.noseRegion[0].y - 0.05)]

        let baseAngles = try angles(base)
        let lowerAngles = try angles(lower)
        #expect(lowerAngles.pitch > baseAngles.pitch)
        #expect(abs(lowerAngles.yaw) < 1e-9)
    }

    @Test func noseMovingTowardImageRightRaisesYaw() throws {
        let base = points()
        var right = base
        right.noseRegion = [CGPoint(x: base.noseRegion[0].x + 0.05, y: base.noseRegion[0].y)]
        let rightAngles = try angles(right)
        let baseAngles = try angles(base)
        #expect(rightAngles.yaw > baseAngles.yaw)
    }

    @Test func arcsineExtensionIsContinuousMonotonicAndFinite() {
        #expect(abs(LandmarkGeometry.extendedArcsine(0.5) - asin(0.5)) < 1e-12)
        #expect(abs(LandmarkGeometry.extendedArcsine(-0.5) + asin(0.5)) < 1e-12)
        #expect(LandmarkGeometry.extendedArcsine(0) == 0)
        let inputs = Array(stride(from: -2.0, through: 2.0, by: 0.01))
        let outputs = inputs.map(LandmarkGeometry.extendedArcsine)
        for (previous, next) in zip(outputs, outputs.dropFirst()) {
            #expect(next > previous)
            #expect(next - previous < 0.05)  // no jump at the 0.9 seam: slope 2.3 times a 0.01 step
        }
        #expect(outputs.allSatisfy { $0.isFinite })
        #expect(LandmarkGeometry.extendedArcsine(50) == LandmarkGeometry.extendedArcsine(2))
    }

    @Test func pitchKeepsRespondingWhenTheNoseIsLowerThanTheModelAllows() throws {
        // A long nose: 0.9 inter-ocular distances below the eye line, beyond the model's farthest drop of 0.75.
        let base = points()
        let tip = base.noseRegion[0]
        let eyeY = try center(base.leftEyeRegion).y
        var longNose = base
        longNose.noseRegion = [CGPoint(x: tip.x, y: eyeY - 0.9 * 0.3)]
        var longerNose = base
        longerNose.noseRegion = [CGPoint(x: tip.x, y: eyeY - 0.95 * 0.3)]
        let first = try angles(longNose)
        let second = try angles(longerNose)
        #expect(second.pitch > first.pitch)
        #expect(first.pitch.isFinite)
    }

    @Test func extremeInputsStayFiniteAndYawStaysBounded() throws {
        var high = points()
        high.noseRegion = [CGPoint(x: 5, y: 5)]
        var low = points()
        low.noseRegion = [CGPoint(x: -5, y: -5)]
        for extreme in [high, low] {
            let result = try angles(extreme)
            #expect(result.yaw.isFinite && abs(result.yaw) <= 90)
            #expect(result.pitch.isFinite)
        }
    }

    // MARK: Invariances

    @Test(arguments: [-40.0, -15, 15, 40])
    func rollDoesNotChangeTheResult(roll: Double) throws {
        let upright = try angles(points(yawDegrees: 20, pitchUpDegrees: 10))
        let rolled = try angles(points(yawDegrees: 20, pitchUpDegrees: 10, rollDegrees: roll))
        #expect(abs(upright.yaw - rolled.yaw) < 1e-6)
        #expect(abs(upright.pitch - rolled.pitch) < 1e-6)
    }

    @Test func eyeOrderDoesNotMatter() throws {
        let original = points(yawDegrees: 25, pitchUpDegrees: -10)
        var swapped = original
        swapped.leftEyeRegion = original.rightEyeRegion
        swapped.rightEyeRegion = original.leftEyeRegion
        let first = try angles(original)
        let second = try angles(swapped)
        #expect(abs(first.yaw - second.yaw) < 1e-9)
        #expect(abs(first.pitch - second.pitch) < 1e-9)
    }

    @Test func nonSquareFaceBoxIsCompensatedForByTheAspectRatio() throws {
        // The same head rendered into a box that is 1.25x wider than tall (in pixels).
        let aspect = 1.25
        let result = try angles(points(yawDegrees: 20, pitchUpDegrees: 0, aspect: aspect), aspect: aspect)
        #expect(abs(result.yaw - 20) < 1e-6)
        #expect(abs(result.pitch) < 1e-6)
    }

    @Test func faceInADifferentPlaceInTheBoxGivesTheSameAngles() throws {
        let a = try angles(points(yawDegrees: -15, pitchUpDegrees: 20, center: CGPoint(x: 0.45, y: 0.55)))
        let b = try angles(points(yawDegrees: -15, pitchUpDegrees: 20, center: CGPoint(x: 0.6, y: 0.7)))
        #expect(abs(a.yaw - b.yaw) < 1e-9)
        #expect(abs(a.pitch - b.pitch) < 1e-9)
    }

    // MARK: Missing landmarks

    @Test func missingEyeRegionGivesNil() {
        var noLeft = points()
        noLeft.leftEyeRegion = []
        #expect(LandmarkGeometry.angles(from: noLeft) == nil)

        var noRight = points()
        noRight.rightEyeRegion = []
        #expect(LandmarkGeometry.angles(from: noRight) == nil)

        var neither = points()
        neither.leftEyeRegion = []
        neither.rightEyeRegion = []
        #expect(LandmarkGeometry.angles(from: neither) == nil)

        var onlyNonFinite = points()
        onlyNonFinite.leftEyeRegion = [CGPoint(x: Double.nan, y: 0.5)]
        #expect(LandmarkGeometry.angles(from: onlyNonFinite) == nil)
    }

    @Test func missingNoseGivesNil() {
        var noNose = points()
        noNose.noseRegion = []
        noNose.noseCrestRegion = []
        #expect(LandmarkGeometry.angles(from: noNose) == nil)
        #expect(LandmarkGeometry.angles(from: LandmarkGeometry.Points()) == nil)
    }

    @Test func degenerateInputsGiveNil() {
        var coincidentEyes = points()
        coincidentEyes.rightEyeRegion = coincidentEyes.leftEyeRegion
        #expect(LandmarkGeometry.angles(from: coincidentEyes) == nil)

        var notANumber = points()
        notANumber.noseRegion = [CGPoint(x: Double.nan, y: 0.3)]
        #expect(LandmarkGeometry.angles(from: notANumber) == nil)

        #expect(LandmarkGeometry.angles(from: points(), boxAspect: 0) == nil)
        #expect(LandmarkGeometry.angles(from: points(), boxAspect: .nan) == nil)
    }

    // MARK: Reference point selection

    @Test func eyeCenterIsTheCentroidOfTheEyeRegionOutline() throws {
        // An irregular outline: the centroid is the plain mean of its points, (0.3, 0.5) here.
        let region = [
            CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.35, y: 0.58), CGPoint(x: 0.25, y: 0.42),
        ]
        let eye = try center(region)
        #expect(abs(eye.x - 0.3) < 1e-12)
        #expect(abs(eye.y - 0.5) < 1e-12)
        // Non-finite points are ignored; an outline with no usable point has no center.
        let withNaN = try center(region + [CGPoint(x: Double.nan, y: 0.9)])
        #expect(abs(withNaN.x - 0.3) < 1e-12)
        #expect(abs(withNaN.y - 0.5) < 1e-12)
        #expect(LandmarkGeometry.eyeCenter(region: []) == nil)
        #expect(LandmarkGeometry.eyeCenter(region: [CGPoint(x: Double.infinity, y: 0)]) == nil)
    }

    @Test func anglesUseTheEyeRegionCentroidsAsEyeCenters() throws {
        // Lopsided outlines (more points on one side, as a real contour can have): the proxy must follow their
        // centroids exactly, whatever their shape.
        let reference = points(yawDegrees: 15, pitchUpDegrees: 5)
        var lopsided = reference
        lopsided.leftEyeRegion += reference.leftEyeRegion.prefix(3)
        lopsided.rightEyeRegion += reference.rightEyeRegion.suffix(2)
        let left = try center(lopsided.leftEyeRegion)
        let right = try center(lopsided.rightEyeRegion)
        let nose = try #require(lopsided.noseRegion.first)

        let expected = try #require(LandmarkGeometry.angles(firstEye: left, secondEye: right, noseTip: nose))
        let actual = try angles(lopsided)
        #expect(abs(expected.yaw - actual.yaw) < 1e-9)
        #expect(abs(expected.pitch - actual.pitch) < 1e-9)
        // The extra points pull the centroids, so the result differs from the symmetric reference.
        #expect(abs(actual.yaw - (try angles(reference)).yaw) > 1e-6)
    }

    @Test func noseTipIsTheMeanOfTheOutlineCentroidAndTheFarthestCrestPoint() {
        let eyeMidpoint = CGPoint(x: 0.5, y: 0.6)
        let outline = [CGPoint(x: 0.45, y: 0.3), CGPoint(x: 0.55, y: 0.3)]  // centroid (0.5, 0.3)
        // Crest listed bridge-first here; the tip is the point farthest from the eyes either way.
        let crest = [CGPoint(x: 0.5, y: 0.55), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 0.5, y: 0.34)]
        let expected = CGPoint(x: 0.5, y: 0.32)
        let forward = LandmarkGeometry.noseTip(noseRegion: outline, noseCrestRegion: crest, eyeMidpoint: eyeMidpoint)
        let reversed = LandmarkGeometry.noseTip(
            noseRegion: outline, noseCrestRegion: crest.reversed(), eyeMidpoint: eyeMidpoint)
        #expect(forward == expected)
        #expect(reversed == expected)
    }

    @Test func noseTipFallsBackToWhicheverRegionExists() {
        let eyeMidpoint = CGPoint(x: 0.5, y: 0.6)
        let outline = [CGPoint(x: 0.4, y: 0.3), CGPoint(x: 0.6, y: 0.3)]
        let crest = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.35)]
        #expect(
            LandmarkGeometry.noseTip(noseRegion: outline, noseCrestRegion: [], eyeMidpoint: eyeMidpoint)
                == CGPoint(x: 0.5, y: 0.3))
        #expect(
            LandmarkGeometry.noseTip(noseRegion: [], noseCrestRegion: crest, eyeMidpoint: eyeMidpoint)
                == CGPoint(x: 0.5, y: 0.35))
        #expect(LandmarkGeometry.noseTip(noseRegion: [], noseCrestRegion: [], eyeMidpoint: eyeMidpoint) == nil)
    }
}
