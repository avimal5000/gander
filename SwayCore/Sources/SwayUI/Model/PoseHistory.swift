import Foundation
import SwayModels

/// One face sample kept for the live yaw/pitch plot.
struct PoseHistoryPoint: Identifiable, Equatable {
    /// Monotonic sequence number; stable identity for chart marks.
    let id: Int
    /// Sample timestamp (seconds, monotonic clock).
    let timestamp: TimeInterval
    let pose: HeadPose
}

/// Rolling window of recent samples: the last 10 s of face poses for plots, and the sample timestamps of the last
/// 2 s for the measured frame rate. A plain value type so it is trivially testable.
struct PoseHistory: Equatable {
    /// Seconds of face poses kept for the plot.
    static let plotWindow: TimeInterval = 10
    /// Seconds of sample timestamps used for the frame-rate measurement.
    static let fpsWindow: TimeInterval = 2

    /// Face samples within `plotWindow` of the newest sample, oldest first. Frames without a face leave a gap.
    private(set) var points: [PoseHistoryPoint] = []
    private var timestamps: [TimeInterval] = []
    private var nextID = 0

    /// Samples per second over the last `fpsWindow` seconds (counting frames with and without a face).
    /// Zero until two samples have arrived.
    var fps: Double {
        guard let first = timestamps.first, let last = timestamps.last, timestamps.count >= 2, last > first else {
            return 0
        }
        return Double(timestamps.count - 1) / (last - first)
    }

    /// Adds a sample and drops anything that fell out of the windows. A timestamp that goes backwards means a
    /// new timeline, so the history restarts.
    mutating func append(_ sample: PoseSample) {
        if let last = timestamps.last, sample.timestamp < last {
            reset()
        }
        timestamps.append(sample.timestamp)
        let fpsCutoff = sample.timestamp - Self.fpsWindow
        if let firstKept = timestamps.firstIndex(where: { $0 >= fpsCutoff }), firstKept > 0 {
            timestamps.removeFirst(firstKept)
        }

        if let pose = sample.pose {
            points.append(PoseHistoryPoint(id: nextID, timestamp: sample.timestamp, pose: pose))
            nextID += 1
        }
        let plotCutoff = sample.timestamp - Self.plotWindow
        if let firstKept = points.firstIndex(where: { $0.timestamp >= plotCutoff }) {
            if firstKept > 0 { points.removeFirst(firstKept) }
        } else {
            points.removeAll()
        }
    }

    /// Forgets everything (camera stopped or restarted).
    mutating func reset() {
        points.removeAll()
        timestamps.removeAll()
    }
}
