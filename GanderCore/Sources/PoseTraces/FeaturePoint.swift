import GanderModels

/// A 2-D feature vector: `x` is the yaw-like axis, `y` the pitch-like axis, in degrees.
struct FeaturePoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

extension PoseFeatureSet {
    /// The feature point of `pose` for this feature set, or `nil` when the pose lacks the features
    /// (landmarks unavailable).
    func point(of pose: HeadPose) -> FeaturePoint? {
        switch self {
        case .visionAngles:
            return FeaturePoint(x: pose.yaw, y: pose.pitch)
        case .landmarkAngles:
            guard let x = pose.landmarkYaw, let y = pose.landmarkPitch else { return nil }
            return FeaturePoint(x: x, y: y)
        }
    }
}
