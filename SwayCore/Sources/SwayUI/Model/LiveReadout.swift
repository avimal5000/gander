import Foundation
import SwayModels

/// What the numeric text readouts show (yaw, pitch, roll, confidence, frame rate): the latest pose and frame rate,
/// refreshed at most `refreshInterval` apart in sample time. A plain value type so it is trivially testable.
///
/// Re-laying out about ten changing labels on every camera frame was most of the Pose Debug window's CPU once the plot
/// was fixed, and numbers changing 15 times a second cannot be read anyway. The plot, the face box, and the switch
/// preview still follow every frame.
struct LiveReadout: Equatable {
    static let refreshInterval: TimeInterval = 0.2

    /// The pose at the last refresh; `nil` without a face or with the camera off.
    private(set) var pose: HeadPose?
    /// Measured frame rate at the last refresh.
    private(set) var fps: Double = 0
    /// Sample time of the last refresh; `nil` before the first sample.
    private(set) var timestamp: TimeInterval?

    init() {}

    init(sample: PoseSample, fps: Double) {
        pose = sample.pose
        self.fps = fps
        timestamp = sample.timestamp
    }

    /// True if `sample` should replace this readout: the first sample, a face appearing or disappearing (shown at
    /// once), `refreshInterval` after the last refresh, or time going backwards (a new timeline).
    func isDue(for sample: PoseSample) -> Bool {
        guard let timestamp else { return true }
        if (pose == nil) != (sample.pose == nil) { return true }
        let elapsed = sample.timestamp - timestamp
        return elapsed < 0 || elapsed >= Self.refreshInterval
    }
}
