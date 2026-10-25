import CoreGraphics
import Foundation
import SwayModels
import Testing
import Vision

@testable import PoseEstimator

@Suite("VisionPoseEstimator")
struct VisionPoseEstimatorTests {
    private func observation(
        box: CGRect = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
        roll: Double? = 0.1,
        yaw: Double? = 0.2,
        pitch: Double? = -0.3
    ) -> VNFaceObservation {
        VNFaceObservation(
            requestRevision: 3,
            boundingBox: box,
            roll: roll.map { NSNumber(value: $0) },
            yaw: yaw.map { NSNumber(value: $0) },
            pitch: pitch.map { NSNumber(value: $0) }
        )
    }

    @Test func blankFrameHasNoFace() {
        let estimator = VisionPoseEstimator()
        let frame = TestPixelBuffer.frame(timestamp: 0)
        #expect(estimator.estimate(frame) == nil)
        // A second call on the same instance behaves the same: no state leaks between frames.
        #expect(estimator.estimate(frame) == nil)
    }

    @Test func blankFrameOfAnotherSizeHasNoFace() {
        let frame = CameraFrame(pixelBuffer: TestPixelBuffer.blank(width: 320, height: 240), timestamp: 1)
        #expect(VisionPoseEstimator().estimate(frame) == nil)
    }

    @Test func estimatorCanBeUsedFromSeveralTasks() async {
        let estimator = VisionPoseEstimator()
        let results = await withTaskGroup(of: HeadPose?.self) { group in
            for index in 0..<4 {
                group.addTask { estimator.estimate(TestPixelBuffer.frame(timestamp: Double(index))) }
            }
            var all: [HeadPose?] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results.count == 4)
        #expect(results.allSatisfy { $0 == nil })
    }

    @Test func largestFaceIsTheOneWithTheBiggestBoundingBoxArea() {
        let small = observation(box: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
        let tall = observation(box: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.5))
        let wide = observation(box: CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.2))
        #expect(VisionPoseEstimator.largestFace(in: [small, tall, wide]) === tall)
        #expect(VisionPoseEstimator.largestFace(in: [wide, small]) === wide)
        #expect(VisionPoseEstimator.largestFace(in: []) == nil)
    }

    @Test func equalAreasPickTheFirstObservation() {
        let first = observation(box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
        let second = observation(box: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))
        #expect(VisionPoseEstimator.largestFace(in: [first, second]) === first)
    }

    @Test func anglesConvertFromRadiansToDegrees() {
        let face = observation(roll: .pi / 6, yaw: .pi / 4, pitch: -.pi / 9)
        let pose = VisionPoseEstimator().makeHeadPose(from: face, landmarkAngles: nil)
        #expect(abs(pose.roll - 30) < 1e-4)
        #expect(abs(pose.yaw - 45) < 1e-4)
        #expect(abs(pose.pitch - (-20)) < 1e-4)
        #expect(pose.faceBounds == face.boundingBox)
        #expect(pose.faceConfidence == Double(face.confidence))
        #expect(pose.landmarkYaw == nil)
        #expect(pose.landmarkPitch == nil)
    }

    @Test func missingAnglesBecomeZero() {
        let face = observation(roll: nil, yaw: 0.5, pitch: nil)
        let pose = VisionPoseEstimator().makeHeadPose(from: face, landmarkAngles: nil)
        #expect(pose.pitch == 0)
        #expect(pose.roll == 0)
        #expect(abs(pose.yaw - 0.5 * 180 / .pi) < 1e-9)
    }

    @Test func landmarkAnglesAreCarriedIntoThePose() {
        let angles = LandmarkGeometry.Angles(yaw: 12.5, pitch: -3.5)
        let pose = VisionPoseEstimator().makeHeadPose(from: observation(), landmarkAngles: angles)
        #expect(pose.landmarkYaw == 12.5)
        #expect(pose.landmarkPitch == -3.5)
    }
}
