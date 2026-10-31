import CoreGraphics
import Foundation

/// Head orientation of the most prominent face in one camera frame.
///
/// Angles are in degrees, in Vision's raw sign convention on the unmirrored camera image.
/// Only consistency matters for classification; the sign observed on real hardware is
/// recorded in the M1 gate report.
public struct HeadPose: Sendable, Equatable, Codable {
    /// Vision yaw (`VNFaceObservation.yaw`), degrees.
    public var yaw: Double
    /// Vision pitch (`VNFaceObservation.pitch`), degrees.
    public var pitch: Double
    /// Vision roll (`VNFaceObservation.roll`), degrees.
    public var roll: Double
    /// Face detection confidence, 0...1 (`VNFaceObservation.confidence`).
    public var faceConfidence: Double
    /// Face bounding box in normalized image coordinates (0...1, origin bottom-left, Vision convention).
    public var faceBounds: CGRect
    /// Landmark-derived yaw proxy in degree-equivalents; `nil` when landmarks are unavailable.
    /// Continuous, about 0 when facing the camera, monotonic with head rotation.
    public var landmarkYaw: Double?
    /// Landmark-derived pitch proxy in degree-equivalents; `nil` when landmarks are unavailable.
    public var landmarkPitch: Double?

    public init(
        yaw: Double,
        pitch: Double,
        roll: Double,
        faceConfidence: Double,
        faceBounds: CGRect = .zero,
        landmarkYaw: Double? = nil,
        landmarkPitch: Double? = nil
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.faceConfidence = faceConfidence
        self.faceBounds = faceBounds
        self.landmarkYaw = landmarkYaw
        self.landmarkPitch = landmarkPitch
    }
}

/// One processed camera frame: a timestamp plus the head pose, if a face was found.
public struct PoseSample: Sendable, Equatable, Codable {
    /// Seconds on a monotonic clock (frame presentation time). Only differences are meaningful.
    public var timestamp: TimeInterval
    /// `nil` when no face was detected in the frame.
    public var pose: HeadPose?

    public init(timestamp: TimeInterval, pose: HeadPose?) {
        self.timestamp = timestamp
        self.pose = pose
    }
}
