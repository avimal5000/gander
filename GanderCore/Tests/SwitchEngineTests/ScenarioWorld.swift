import CoreGraphics
import Foundation
import GanderModels

@testable import SwitchEngine

/// The three-display set-up of the synthetic scenarios (CONTRACT section 6.6): display yaws 61 / 42 / 2 and
/// pitches 5 / 10 / 8 degrees, left to right, with calibration noise of 1.5 degrees in yaw and 2.5 in pitch.
enum ScenarioWorld {
    static let ids: [DisplayID] = ["scenario-left", "scenario-middle", "scenario-right"]
    static let yaws = [61.0, 42.0, 2.0]
    static let pitches = [5.0, 10.0, 8.0]
    static let yawStd = 1.5
    static let pitchStd = 2.5
    static let frameRate = 15.0

    static var left: DisplayID { ids[0] }
    static var middle: DisplayID { ids[1] }
    static var right: DisplayID { ids[2] }

    /// Where the head points when looking at the center of `display`.
    static func target(_ display: DisplayID) -> PoseScript.Target {
        guard let index = ids.firstIndex(of: display) else { return PoseScript.Target(yaw: 0, pitch: 0) }
        return PoseScript.Target(yaw: yaws[index], pitch: pitches[index])
    }

    /// A labeled two-round gate trace of 75 samples per display and round, like the real gate test.
    static func calibrationTrace(seed: UInt64) -> PoseTrace {
        var rng = SplitMix64(seed: seed)
        var segments: [TraceSegment] = []
        var frame = 0
        for round in 1...2 {
            for (index, id) in ids.enumerated() {
                var samples: [PoseSample] = []
                for _ in 0..<75 {
                    let pose = makePose(
                        yaw: yaws[index] + rng.nextGaussian() * yawStd,
                        pitch: pitches[index] + rng.nextGaussian() * pitchStd
                    )
                    samples.append(PoseSample(timestamp: Double(frame) / frameRate, pose: pose))
                    frame += 1
                }
                segments.append(TraceSegment(displayID: id, round: round, samples: samples))
            }
        }
        return PoseTrace(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            cameraName: "Synthetic",
            layout: makeLayout(ids),
            segments: segments
        )
    }

    /// The profile fitted, with the real engine, from a synthetic labeled trace.
    static func profile(seed: UInt64 = 2026) throws -> CalibrationProfile {
        try PoseSwitchEngine().fitProfile(from: calibrationTrace(seed: seed), features: .visionAngles, rounds: nil)
    }
}
