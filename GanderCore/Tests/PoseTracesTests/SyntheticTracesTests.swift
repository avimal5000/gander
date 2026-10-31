import CoreGraphics
import Foundation
import GanderModels
import Testing

@testable import PoseTraces

@Suite struct SyntheticTracesTests {
    private func trace(
        clusters: [SyntheticCluster] = leftRightClusters,
        std: Double = 3,
        samples: Int = 40,
        rounds: Int = 2,
        drop: Double = 0,
        frameRate: Double = 15,
        seed: UInt64 = 42
    ) -> PoseTrace {
        SyntheticTraces.gateTrace(
            clusters: clusters,
            std: std,
            samplesPerSegment: samples,
            rounds: rounds,
            faceDropRate: drop,
            frameRate: frameRate,
            seed: seed
        )
    }

    @Test func sameSeedGivesIdenticalTracesAndDifferentSeedsDiffer() {
        #expect(trace(seed: 42) == trace(seed: 42))
        #expect(trace(drop: 0.3, seed: 42) == trace(drop: 0.3, seed: 42))
        let other = trace(seed: 43)
        #expect(trace(seed: 42) != other)
        #expect(trace(seed: 42).id != other.id)
        #expect(trace(seed: 42).segments != other.segments)
    }

    @Test func segmentsAreRoundMajorInClusterOrder() {
        let clusters = leftRightClusters + [SyntheticCluster(displayID: .top, yaw: 0, pitch: 20)]
        let result = trace(clusters: clusters, samples: 7, rounds: 3)
        #expect(result.segments.count == 9)
        let labels = result.segments.map { "\($0.displayID?.rawValue ?? "-")#\($0.round)" }
        #expect(
            labels == [
                "left#1", "right#1", "top#1",
                "left#2", "right#2", "top#2",
                "left#3", "right#3", "top#3",
            ]
        )
        #expect(result.segments.allSatisfy { $0.samples.count == 7 })
    }

    @Test func timestampsAdvanceByOneFrameContinuouslyAcrossSegments() {
        let result = trace(samples: 5, rounds: 2, frameRate: 20)
        let timestamps = result.segments.flatMap(\.samples).map(\.timestamp)
        #expect(timestamps.count == 20)
        for (index, timestamp) in timestamps.enumerated() {
            #expect(abs(timestamp - Double(index) / 20) < 1e-12)
        }
    }

    @Test func defaultFrameRateIsThePolicyRate() {
        let result = SyntheticTraces.gateTrace(
            clusters: leftRightClusters,
            std: 1,
            samplesPerSegment: 3,
            rounds: 1,
            seed: 1
        )
        let timestamps = result.segments.flatMap(\.samples).map(\.timestamp)
        #expect(abs(timestamps[1] - 1 / GanderPolicy.defaultFrameRate) < 1e-12)
    }

    @Test func layoutHasOneWideDisplayPerClusterLeftToRight() throws {
        let clusters = leftRightClusters + [SyntheticCluster(displayID: .top, yaw: 0, pitch: 20)]
        let result = trace(clusters: clusters)
        let layout = try #require(result.layout)
        #expect(layout.displays.map(\.id) == [.left, .right, .top])
        #expect(layout.displays.map(\.name) == ["Display 1", "Display 2", "Display 3"])
        #expect(layout.displays.allSatisfy { $0.frame.size == CGSize(width: 1920, height: 1080) })
        #expect(layout.displays.map(\.frame.origin.x) == [0, 1920, 3840])
        #expect(Set(layout.displays.map(\.cgDisplayID)).count == 3)
        #expect(result.cameraName == "Synthetic")
        #expect(result.formatVersion == PoseTrace.currentFormatVersion)
    }

    @Test func posesHaveConstantConfidenceAndCenteredFaceBounds() {
        let poses = trace().segments.flatMap(\.samples).compactMap(\.pose)
        #expect(!poses.isEmpty)
        for pose in poses {
            #expect(pose.faceConfidence == 0.95)
            #expect(abs(pose.faceBounds.midX - 0.5) < 1e-12)
            #expect(abs(pose.faceBounds.midY - 0.5) < 1e-12)
            #expect(pose.landmarkYaw != nil && pose.landmarkPitch != nil)
        }
    }

    @Test func sampleStatisticsFollowTheDocumentedDistributions() throws {
        let clusters = [SyntheticCluster(displayID: .left, yaw: -20, pitch: 5)]
        let result = trace(clusters: clusters, std: 3, samples: 4000, rounds: 1)
        let poses = result.segments.flatMap(\.samples).compactMap(\.pose)

        func summary(_ values: [Double]) -> (mean: Double, std: Double) {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
            return (mean, variance.squareRoot())
        }
        let yaw = summary(poses.map(\.yaw))
        let pitch = summary(poses.map(\.pitch))
        let roll = summary(poses.map(\.roll))
        let landmarkYaw = summary(poses.compactMap(\.landmarkYaw))
        let landmarkPitch = summary(poses.compactMap(\.landmarkPitch))

        #expect(abs(yaw.mean - -20) < 0.3)
        #expect(abs(yaw.std - 3) < 0.2)
        #expect(abs(pitch.mean - 5) < 0.3)
        #expect(abs(pitch.std - 3) < 0.2)
        #expect(abs(roll.mean) < 0.1)
        #expect(abs(roll.std - 1) < 0.1)
        // landmark = 0.9 * angle + N(0, std / 2): mean 0.9 * center, std sqrt((0.9 * 3)² + 1.5²)
        let expectedLandmarkStd = (2.7 * 2.7 + 1.5 * 1.5).squareRoot()
        #expect(abs(landmarkYaw.mean - -18) < 0.3)
        #expect(abs(landmarkYaw.std - expectedLandmarkStd) < 0.2)
        #expect(abs(landmarkPitch.mean - 4.5) < 0.3)
        #expect(abs(landmarkPitch.std - expectedLandmarkStd) < 0.2)
    }

    @Test func dropRateRemovesThatFractionOfEachSegment() {
        let result = trace(samples: 40, rounds: 3, drop: 0.25)
        for segment in result.segments {
            #expect(segment.samples.filter { $0.pose == nil }.count == 10)
        }
        // The drops are spread by the PRNG rather than clustered at the start or end of the segment.
        let droppedIndices = result.segments[0].samples.enumerated().filter { $0.element.pose == nil }.map(\.offset)
        #expect(droppedIndices != Array(0..<10))
        #expect(droppedIndices != Array(30..<40))
    }

    @Test func dropRateEdgesAndClamping() {
        #expect(trace(drop: 0).segments.allSatisfy { $0.samples.allSatisfy { $0.pose != nil } })
        #expect(trace(drop: 1).segments.allSatisfy { $0.samples.allSatisfy { $0.pose == nil } })
        #expect(trace(drop: 5).segments.allSatisfy { $0.samples.allSatisfy { $0.pose == nil } })
        #expect(trace(drop: -1).segments.allSatisfy { $0.samples.allSatisfy { $0.pose != nil } })
    }

    @Test func dropRateDoesNotChangeTheRemainingPoseValues() {
        let full = trace(drop: 0)
        let thinned = trace(drop: 0.4)
        for (fullSegment, thinnedSegment) in zip(full.segments, thinned.segments) {
            for (fullSample, thinnedSample) in zip(fullSegment.samples, thinnedSegment.samples) {
                #expect(fullSample.timestamp == thinnedSample.timestamp)
                if let pose = thinnedSample.pose {
                    #expect(pose == fullSample.pose)
                }
            }
        }
    }

    @Test func degenerateArgumentsProduceEmptyButValidTraces() {
        #expect(trace(rounds: 0).segments.isEmpty)
        #expect(trace(rounds: -2).segments.isEmpty)
        #expect(trace(clusters: []).segments.isEmpty)
        #expect(trace(samples: 0).segments.allSatisfy { $0.samples.isEmpty })
        #expect(trace(samples: -5).segments.allSatisfy { $0.samples.isEmpty })
        // A non-positive frame rate falls back to the policy default rather than dividing by zero.
        let timestamps = trace(samples: 3, rounds: 1, frameRate: 0).segments.flatMap(\.samples).map(\.timestamp)
        #expect(timestamps.allSatisfy { $0.isFinite })
    }

    @Test func syntheticTraceSurvivesAJSONRoundTrip() throws {
        let original = trace(drop: 0.1)
        let data = try FileTraceStore.makeEncoder().encode(original)
        let decoded = try FileTraceStore.makeDecoder().decode(PoseTrace.self, from: data)
        #expect(decoded == original)
    }
}
