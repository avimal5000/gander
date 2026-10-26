import CoreGraphics
import Foundation
import SwayModels
import os

/// A deterministic `PoseEstimating`: the pose is a pure function of the frame timestamp, so tests can tell
/// which frame produced which sample. A negative timestamp means "no face", unless the test gives `hasFace`, which
/// then decides for every timestamp (so a scripted stream of increasing times can still have faces come and go).
final class FakePoseEstimator: PoseEstimating {
    private struct Calls {
        var timestamps: [TimeInterval] = []
        var includeLandmarks: [Bool] = []
    }

    private let calls = OSAllocatedUnfairLock(initialState: Calls())
    private let hasFace: @Sendable (TimeInterval) -> Bool

    init(hasFace: @escaping @Sendable (TimeInterval) -> Bool = { $0 >= 0 }) {
        self.hasFace = hasFace
    }

    /// Timestamps of every frame estimated so far, in call order.
    var estimatedTimestamps: [TimeInterval] { calls.withLock { $0.timestamps } }

    /// The `includeLandmarks` flag received by each call so far, in call order.
    var receivedIncludeLandmarks: [Bool] { calls.withLock { $0.includeLandmarks } }

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

    func estimate(_ frame: CameraFrame, includeLandmarks: Bool) -> HeadPose? {
        calls.withLock {
            $0.timestamps.append(frame.timestamp)
            $0.includeLandmarks.append(includeLandmarks)
        }
        guard hasFace(frame.timestamp) else { return nil }
        return Self.pose(at: abs(frame.timestamp))
    }
}
