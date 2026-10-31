import Foundation
import GanderModels

/// Deterministic synthetic traces for tests and previews. Numeric only; nothing here touches a camera.
public enum SyntheticTraces {
    /// Builds a labeled gate trace: for each round and each cluster (in order) one segment of
    /// `samplesPerSegment` samples.
    ///
    /// The result is fully determined by the arguments: identical arguments (including `seed`) yield an
    /// identical trace, including its `id` and `createdAt`. Randomness comes from `SplitMix64`.
    ///
    /// - Parameters:
    ///   - clusters: one entry per display the simulated user looks at, in gaze order.
    ///   - std: standard deviation of yaw and pitch around the cluster center, degrees.
    ///   - samplesPerSegment: frames per (round, cluster) segment.
    ///   - rounds: number of rounds; segments carry the 1-based round number.
    ///   - faceDropRate: fraction (0...1) of each segment's samples whose pose is `nil`. The count is
    ///     `round(rate × samplesPerSegment)` per segment and the affected samples are chosen by the PRNG.
    ///   - frameRate: timestamps advance by `1 / frameRate` per sample, continuously across segments.
    ///   - seed: PRNG seed.
    public static func gateTrace(
        clusters: [SyntheticCluster],
        std: Double,
        samplesPerSegment: Int,
        rounds: Int,
        faceDropRate: Double = 0,
        frameRate: Double = GanderPolicy.defaultFrameRate,
        seed: UInt64
    ) -> PoseTrace {
        // Independent streams so that the drop rate never changes the pose values of the remaining samples.
        var poseRandom = SplitMix64(seed: seed)
        var dropRandom = SplitMix64(seed: seed ^ 0xD1B5_4A32_D192_ED03)
        var idRandom = SplitMix64(seed: seed ^ 0x8CB9_2BA7_2F3D_8DD7)

        let effectiveFrameRate = frameRate > 0 && frameRate.isFinite ? frameRate : GanderPolicy.defaultFrameRate
        let sampleCount = max(0, samplesPerSegment)
        let dropFraction = min(max(faceDropRate, 0), 1)
        let dropCount = Int((Double(sampleCount) * dropFraction).rounded())

        var segments: [TraceSegment] = []
        var frameIndex = 0
        for round in stride(from: 1, through: rounds, by: 1) {
            for cluster in clusters {
                let dropped = dropRandom.pickDistinctIndices(count: dropCount, from: sampleCount)
                var samples: [PoseSample] = []
                samples.reserveCapacity(sampleCount)
                for index in 0..<sampleCount {
                    // Always draw the pose so the stream does not depend on which samples are dropped.
                    let pose = makePose(cluster: cluster, std: std, random: &poseRandom)
                    samples.append(
                        PoseSample(
                            timestamp: Double(frameIndex) / effectiveFrameRate,
                            pose: dropped.contains(index) ? nil : pose
                        )
                    )
                    frameIndex += 1
                }
                segments.append(TraceSegment(displayID: cluster.displayID, round: round, samples: samples))
            }
        }

        return PoseTrace(
            id: makeID(from: &idRandom),
            createdAt: referenceDate,
            cameraName: "Synthetic",
            layout: makeLayout(for: clusters),
            segments: segments,
            notes: "Synthetic trace (seed \(seed))"
        )
    }

    // MARK: - Internals

    /// Fixed creation date (2023-11-14T22:13:20Z, whole seconds) so traces are reproducible.
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// The pose for one frame. Consumes exactly five Gaussian draws.
    private static func makePose(cluster: SyntheticCluster, std: Double, random: inout SplitMix64) -> HeadPose {
        let yaw = cluster.yaw + std * random.nextGaussian()
        let pitch = cluster.pitch + std * random.nextGaussian()
        let roll = random.nextGaussian()
        let landmarkYaw = 0.9 * yaw + (std / 2) * random.nextGaussian()
        let landmarkPitch = 0.9 * pitch + (std / 2) * random.nextGaussian()
        return HeadPose(
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            faceConfidence: 0.95,
            faceBounds: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5),
            landmarkYaw: landmarkYaw,
            landmarkPitch: landmarkPitch
        )
    }

    /// One 1920×1080 display per cluster, placed left to right.
    private static func makeLayout(for clusters: [SyntheticCluster]) -> DisplayLayout {
        let displays = clusters.enumerated().map { index, cluster in
            DisplayInfo(
                id: cluster.displayID,
                cgDisplayID: UInt32(index + 1),
                name: "Display \(index + 1)",
                frame: CGRect(x: 1920 * index, y: 0, width: 1920, height: 1080),
                isBuiltIn: false,
                isMain: index == 0
            )
        }
        return DisplayLayout(displays: displays)
    }

    /// A UUID made of 128 PRNG bits.
    private static func makeID(from random: inout SplitMix64) -> UUID {
        let bits = (random.next(), random.next())
        let bytes = withUnsafeBytes(of: bits) { $0.loadUnaligned(as: uuid_t.self) }
        return UUID(uuid: bytes)
    }
}
