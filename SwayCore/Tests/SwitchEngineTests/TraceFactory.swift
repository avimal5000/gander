import Foundation
import SwayModels

/// Builds small labeled traces with exactly known statistics for the fitter tests.
enum TraceFactory {
    static let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    /// A segment of `count` samples whose angles alternate `center + spread, center - spread, ...`. With an even
    /// `count` the mean is exactly `center` and the sample standard deviation is `spread * sqrt(n / (n - 1))`.
    static func segment(
        _ display: DisplayID?,
        round: Int = 1,
        count: Int,
        yaw: Double,
        yawSpread: Double = 1,
        pitch: Double,
        pitchSpread: Double = 1,
        startTime: Double = 0
    ) -> TraceSegment {
        let samples = (0..<count).map { index -> PoseSample in
            let sign = index.isMultiple(of: 2) ? 1.0 : -1.0
            let pose = makePose(
                yaw: yaw + sign * yawSpread,
                pitch: pitch + sign * pitchSpread,
                landmarkYaw: yaw * 0.9 + sign * yawSpread,
                landmarkPitch: pitch * 0.9 + sign * pitchSpread
            )
            return PoseSample(timestamp: startTime + Double(index) / 15, pose: pose)
        }
        return TraceSegment(displayID: display, round: round, samples: samples)
    }

    /// A segment of `count` samples that all have no face.
    static func emptySegment(_ display: DisplayID?, round: Int = 1, count: Int) -> TraceSegment {
        let samples = (0..<count).map { PoseSample(timestamp: Double($0) / 15, pose: nil) }
        return TraceSegment(displayID: display, round: round, samples: samples)
    }

    static func trace(
        _ segments: [TraceSegment],
        layout: DisplayLayout? = nil,
        cameraName: String? = "Test camera"
    ) -> PoseTrace {
        PoseTrace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            createdAt: createdAt,
            cameraName: cameraName,
            layout: layout,
            segments: segments
        )
    }
}
