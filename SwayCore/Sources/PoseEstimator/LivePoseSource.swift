import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The PoseEstimator builder replaces this file. See CONTRACT.md.

/// Live camera pose source: a `FrameSource` feeding a `PoseEstimating`.
public final class LivePoseSource: PoseSource {
    private let frameSource: any FrameSource
    private let estimator: any PoseEstimating

    public init(frameSource: any FrameSource, estimator: any PoseEstimating) {
        self.frameSource = frameSource
        self.estimator = estimator
    }

    public func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        throw CameraError.noDevice
    }

    public func stop() async {}
}
