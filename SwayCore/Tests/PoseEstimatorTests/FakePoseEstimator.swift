import CoreGraphics
import Foundation
import SwayModels
import os

/// A deterministic `PoseEstimating`: the pose is a pure function of the frame timestamp, so tests can tell
/// which frame produced which sample. A negative timestamp means "no face".
final class FakePoseEstimator: PoseEstimating {
    private let calls = OSAllocatedUnfairLock(initialState: [TimeInterval]())

    /// Timestamps of every frame estimated so far, in call order.
    var estimatedTimestamps: [TimeInterval] { calls.withLock { $0 } }

    /// The pose this estimator returns for a timestamp.
    static func pose(at timestamp: TimeInterval) -> HeadPose? {
        guard timestamp >= 0 else { return nil }
        return HeadPose(
            yaw: timestamp * 10,
            pitch: timestamp * -5,
            roll: 0,
            faceConfidence: 0.9,
            faceBounds: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            landmarkYaw: timestamp * 9,
            landmarkPitch: nil
        )
    }

    func estimate(_ frame: CameraFrame) -> HeadPose? {
        calls.withLock { $0.append(frame.timestamp) }
        return Self.pose(at: frame.timestamp)
    }
}
