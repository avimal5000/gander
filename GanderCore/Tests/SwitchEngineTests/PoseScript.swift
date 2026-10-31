import CoreGraphics
import Foundation
import GanderModels

/// Builds a pose stream at 15 fps from holds and linear turns, with seeded Gaussian noise.
///
/// Noise is a multiple of the calibration standard deviations of `ScenarioWorld` (yaw 1.5, pitch 2.5).
struct PoseScript {
    struct Target: Equatable {
        var yaw: Double
        var pitch: Double
    }

    private(set) var samples: [PoseSample] = []
    private(set) var current: Target
    private var rng: SplitMix64
    private var lastFrameWasDrop = false

    init(start: Target, seed: UInt64) {
        current = start
        rng = SplitMix64(seed: seed)
    }

    /// Number of frames covering `seconds`.
    static func frames(for seconds: Double) -> Int {
        Int((seconds * ScenarioWorld.frameRate).rounded())
    }

    /// Stays at `target` for `seconds`. `dropRate` is the chance that a frame loses its face; two drops never
    /// follow each other, so every drop is a single frame. Returns the indices of the samples added.
    @discardableResult
    mutating func hold(at target: Target, seconds: Double, noise: Double = 1, dropRate: Double = 0) -> Range<Int> {
        let first = samples.count
        for _ in 0..<Self.frames(for: seconds) {
            append(target, noise: noise, dropRate: dropRate)
        }
        current = target
        return first..<samples.count
    }

    /// Turns linearly from the current pose to `target` over `seconds`, ending exactly on it.
    @discardableResult
    mutating func turn(to target: Target, seconds: Double, noise: Double = 1) -> Range<Int> {
        let first = samples.count
        let start = current
        let frames = max(1, Self.frames(for: seconds))
        for step in 1...frames {
            let fraction = Double(step) / Double(frames)
            let point = Target(
                yaw: start.yaw + (target.yaw - start.yaw) * fraction,
                pitch: start.pitch + (target.pitch - start.pitch) * fraction
            )
            append(point, noise: noise, dropRate: 0)
        }
        current = target
        return first..<samples.count
    }

    private mutating func append(_ point: Target, noise: Double, dropRate: Double) {
        let timestamp = Double(samples.count) / ScenarioWorld.frameRate
        let drop = !lastFrameWasDrop && dropRate > 0 && rng.nextUnit() < dropRate
        lastFrameWasDrop = drop
        if drop {
            samples.append(PoseSample(timestamp: timestamp, pose: nil))
            return
        }
        let pose = makePose(
            yaw: point.yaw + rng.nextGaussian() * noise * ScenarioWorld.yawStd,
            pitch: point.pitch + rng.nextGaussian() * noise * ScenarioWorld.pitchStd
        )
        samples.append(PoseSample(timestamp: timestamp, pose: pose))
    }
}
