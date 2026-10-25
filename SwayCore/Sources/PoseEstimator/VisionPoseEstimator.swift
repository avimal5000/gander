import CoreGraphics
import CoreVideo
import Foundation
import SwayModels
import Vision
import os

/// Vision-based head pose estimation: face rectangles (roll, yaw, pitch) plus a landmark-geometry proxy.
///
/// Every call builds its own Vision handler and requests, so no Vision object is shared between calls and
/// concurrent use is safe. The pixel buffer is only used inside `estimate(_:)`; nothing is retained or written.
public final class VisionPoseEstimator: PoseEstimating {
    private let logger = SwayLog.logger(category: "pose")
    /// Keys of warnings already logged, so a per-frame condition is logged once and not at frame rate.
    private let loggedKeys = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Face-rectangle request revision 3 when the OS supports it (the first revision with pitch), else `nil`,
    /// which leaves a new request at its latest revision.
    private static let preferredRevision: Int? = {
        let revision = Int(VNDetectFaceRectanglesRequestRevision3)
        return VNDetectFaceRectanglesRequest.supportedRevisions.contains(revision) ? revision : nil
    }()

    public init() {}

    public func estimate(_ frame: CameraFrame, includeLandmarks: Bool) -> HeadPose? {
        let buffer = frame.pixelBuffer
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        if let revision = Self.preferredRevision { faceRequest.revision = revision }
        do {
            try handler.perform([faceRequest])
        } catch {
            logOnce(key: "face-request-failed", "Face detection failed: \(error.localizedDescription)")
            return nil
        }
        guard let face = Self.largestFace(in: faceRequest.results ?? []) else { return nil }

        let angles = landmarkAngles(
            for: face, handler: handler, imageWidth: CVPixelBufferGetWidth(buffer),
            imageHeight: CVPixelBufferGetHeight(buffer))
        return makeHeadPose(from: face, landmarkAngles: angles)
    }

    /// The observation with the largest bounding-box area; the first one wins a tie. `nil` for an empty list.
    static func largestFace(in observations: [VNFaceObservation]) -> VNFaceObservation? {
        var best: VNFaceObservation?
        var bestArea = -Double.infinity
        for observation in observations {
            let area = Double(observation.boundingBox.width * observation.boundingBox.height)
            if area > bestArea {
                best = observation
                bestArea = area
            }
        }
        return best
    }

    /// Builds the pose from a face-rectangles observation: radians to degrees, `0` for an angle Vision did not
    /// compute (logged once).
    func makeHeadPose(from face: VNFaceObservation, landmarkAngles: LandmarkGeometry.Angles?) -> HeadPose {
        HeadPose(
            yaw: degrees(face.yaw, name: "yaw"),
            pitch: degrees(face.pitch, name: "pitch"),
            roll: degrees(face.roll, name: "roll"),
            faceConfidence: Double(face.confidence),
            faceBounds: face.boundingBox,
            landmarkYaw: landmarkAngles?.yaw,
            landmarkPitch: landmarkAngles?.pitch
        )
    }

    /// Runs the landmarks request on the already-detected face and reduces the result to the angle proxy.
    /// Any failure leaves the proxy `nil` without discarding the Vision pose.
    private func landmarkAngles(
        for face: VNFaceObservation,
        handler: VNImageRequestHandler,
        imageWidth: Int,
        imageHeight: Int
    ) -> LandmarkGeometry.Angles? {
        let request = VNDetectFaceLandmarksRequest()
        request.inputFaceObservations = [face]
        do {
            try handler.perform([request])
        } catch {
            logOnce(key: "landmarks-request-failed", "Face landmarks failed: \(error.localizedDescription)")
            return nil
        }
        guard let landmarks = request.results?.first?.landmarks else { return nil }

        // The box is normalized by image size; convert to a pixel aspect ratio for isotropic geometry.
        let box = face.boundingBox
        let boxHeight = Double(box.height) * Double(imageHeight)
        guard boxHeight > 0 else { return nil }
        let boxAspect = Double(box.width) * Double(imageWidth) / boxHeight

        // Eye-region outlines only; pupils follow gaze, not head pose (CONTRACT 6.2).
        let points = LandmarkGeometry.Points(
            leftEyeRegion: landmarks.leftEye?.normalizedPoints ?? [],
            rightEyeRegion: landmarks.rightEye?.normalizedPoints ?? [],
            noseRegion: landmarks.nose?.normalizedPoints ?? [],
            noseCrestRegion: landmarks.noseCrest?.normalizedPoints ?? []
        )
        return LandmarkGeometry.angles(from: points, boxAspect: boxAspect)
    }

    private func degrees(_ radians: NSNumber?, name: String) -> Double {
        guard let radians else {
            logOnce(key: "missing-\(name)", "Vision did not report \(name); using 0")
            return 0
        }
        return radians.doubleValue * 180 / .pi
    }

    private func logOnce(key: String, _ message: String) {
        let isFirst = loggedKeys.withLock { $0.insert(key).inserted }
        if isFirst { logger.warning("\(message, privacy: .public)") }
    }
}
