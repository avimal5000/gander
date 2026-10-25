import CoreGraphics
import Foundation
import SwayModels

@testable import PoseTraces

/// Display IDs used across the tests.
extension DisplayID {
    static let left: DisplayID = "left"
    static let right: DisplayID = "right"
    static let top: DisplayID = "top"
}

/// A head pose with only the angles that matter to the analysis.
func makePose(yaw: Double, pitch: Double, landmarkYaw: Double? = nil, landmarkPitch: Double? = nil) -> HeadPose {
    HeadPose(
        yaw: yaw,
        pitch: pitch,
        roll: 0,
        faceConfidence: 0.95,
        faceBounds: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5),
        landmarkYaw: landmarkYaw,
        landmarkPitch: landmarkPitch
    )
}

/// A labeled segment from `(yaw, pitch)` pairs; landmarks mirror the Vision angles unless `landmarks` is false.
func makeSegment(
    _ displayID: DisplayID?,
    round: Int,
    points: [(Double, Double)],
    landmarks: Bool = true,
    startTime: Double = 0
) -> TraceSegment {
    let samples = points.enumerated().map { index, point in
        PoseSample(
            timestamp: startTime + Double(index) / 15,
            pose: makePose(
                yaw: point.0,
                pitch: point.1,
                landmarkYaw: landmarks ? point.0 : nil,
                landmarkPitch: landmarks ? point.1 : nil
            )
        )
    }
    return TraceSegment(displayID: displayID, round: round, samples: samples)
}

/// Thresholds that never report insufficient data because of sample counts.
let relaxedThresholds = GateThresholds(minFaceSamplesPerDisplay: 1)

/// Two standard clusters used by several tests.
let leftRightClusters = [
    SyntheticCluster(displayID: .left, yaw: -20, pitch: 0),
    SyntheticCluster(displayID: .right, yaw: 20, pitch: 0),
]

/// Runs `body` with a fresh, unique folder URL under the temporary directory (the folder is not created) and
/// removes whatever ended up there afterwards.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SwayPoseTracesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

/// Collects all events of a stream until it finishes.
func collect(_ stream: AsyncStream<PoseSourceEvent>) async -> [PoseSourceEvent] {
    var events: [PoseSourceEvent] = []
    for await event in stream { events.append(event) }
    return events
}
