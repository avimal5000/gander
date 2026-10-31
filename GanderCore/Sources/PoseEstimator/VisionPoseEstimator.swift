import CoreGraphics
import CoreVideo
import Foundation
import GanderModels
import Vision
import os

/// Vision-based head pose estimation: face rectangles (roll, yaw, pitch), plus a landmark-geometry proxy when
/// the caller asks for it.
///
/// The landmark request is a second Vision pass per frame, so it only runs when `estimate(_:includeLandmarks:)`
/// is called with `true` (the gate test). Live tracking passes `false` and uses Vision's angles alone.
///
/// Every call builds its own Vision handler and requests, so no Vision object is shared between calls and
/// concurrent use is safe. The pixel buffer is only used inside `estimate(_:includeLandmarks:)`; nothing is
/// retained or written.
public final class VisionPoseEstimator: PoseEstimating {
    /// A Vision request this estimator can run on a frame.
    enum PlannedRequest: Equatable {
        /// `VNDetectFaceRectanglesRequest`: finds faces and gives roll, yaw, and pitch.
        case faceRectangles
        /// `VNDetectFaceLandmarksRequest`: the eye and nose outlines for the landmark-angle proxy.
        case faceLandmarks
    }

    private let logger = GanderLog.logger(category: "pose")
    /// Keys of warnings already logged, so a per-frame condition is logged once and not at frame rate.
    private let loggedKeys = OSAllocatedUnfairLock(initialState: Set<String>())

    /// The face-rectangle revision to set on each new request: revision 3 (the first with pitch) when the OS
    /// supports it and new requests do not already default to it, else `nil` (leave the request as it is).
    /// Setting a revision is not free (Vision re-reads its private revision table each time, about 3% of a core
    /// at 15 fps), so the setter is skipped when it would change nothing.
    static let revisionOverride: Int? = revisionOverride(
        preferred: Int(VNDetectFaceRectanglesRequestRevision3),
        supported: VNDetectFaceRectanglesRequest.supportedRevisions,
        defaultRevision: VNDetectFaceRectanglesRequest.defaultRevision)

    /// Pure form of `revisionOverride`, for tests.
    static func revisionOverride(preferred: Int, supported: IndexSet, defaultRevision: Int) -> Int? {
        supported.contains(preferred) && defaultRevision != preferred ? preferred : nil
    }

    public init() {}

    /// The requests to run for a frame, in order: face rectangles always, then landmarks only when asked for
    /// (SPEC D15). Pure, so the landmark opt-out is unit-testable without running Vision.
    static func requestPlan(includeLandmarks: Bool) -> [PlannedRequest] {
        includeLandmarks ? [.faceRectangles, .faceLandmarks] : [.faceRectangles]
    }

    /// Estimates the pose of the largest face in `frame`; `nil` if there is none.
    /// - Parameter includeLandmarks: when `false`, only the face-rectangles request runs and the pose's
    ///   `landmarkYaw` / `landmarkPitch` are `nil`. When `true`, the landmarks request also runs on the largest
    ///   face to fill them (they stay `nil` if its eye or nose outlines are missing).
    public func estimate(_ frame: CameraFrame, includeLandmarks: Bool) -> HeadPose? {
        let buffer = frame.pixelBuffer
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        if let revision = Self.revisionOverride { faceRequest.revision = revision }
        do {
            try handler.perform([faceRequest])
        } catch {
            logOnce(key: "face-request-failed", "Face detection failed: \(error.localizedDescription)")
            return nil
        }
        guard let face = Self.largestFace(in: faceRequest.results ?? []) else { return nil }

        let angles: LandmarkGeometry.Angles?
        if Self.requestPlan(includeLandmarks: includeLandmarks).contains(.faceLandmarks) {
            angles = landmarkAngles(
                for: face, handler: handler, imageWidth: CVPixelBufferGetWidth(buffer),
                imageHeight: CVPixelBufferGetHeight(buffer))
        } else {
            angles = nil
        }
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
