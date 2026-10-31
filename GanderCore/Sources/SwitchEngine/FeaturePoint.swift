import GanderModels

/// A pose reduced to the two numbers a feature set classifies on: `x` is the yaw-like axis, `y` the pitch-like
/// axis, both in degrees.
struct FeaturePoint: Sendable, Equatable {
    var x: Double
    var y: Double
}

extension PoseFeatureSet {
    /// The point `pose` has in this feature set, or `nil` when the pose lacks the features.
    ///
    /// - `.visionAngles` always succeeds: (`yaw`, `pitch`).
    /// - `.landmarkAngles` needs both `landmarkYaw` and `landmarkPitch`; live tracking leaves them `nil`
    ///   (SPEC D15), so a landmark profile classifies such poses as no face.
    func point(of pose: HeadPose) -> FeaturePoint? {
        switch self {
        case .visionAngles:
            return FeaturePoint(x: pose.yaw, y: pose.pitch)
        case .landmarkAngles:
            guard let yaw = pose.landmarkYaw, let pitch = pose.landmarkPitch else { return nil }
            return FeaturePoint(x: yaw, y: pitch)
        }
    }
}
