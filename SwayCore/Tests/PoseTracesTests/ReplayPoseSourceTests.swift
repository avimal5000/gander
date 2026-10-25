import Foundation
import SwayModels
import Testing

@testable import PoseTraces

@Suite struct ReplayPoseSourceTests {
    private func smallTrace() -> PoseTrace {
        var trace = SyntheticTraces.gateTrace(
            clusters: leftRightClusters,
            std: 2,
            samplesPerSegment: 4,
            rounds: 2,
            faceDropRate: 0.25,
            seed: 3
        )
        // Include an unlabeled free recording as well; replay emits every segment.
        trace.segments.append(makeSegment(nil, round: 0, points: [(1, 2), (3, 4)], startTime: 100))
        return trace
    }

    /// A trace whose samples are far apart in time, so a real-time replay stays parked after the first sample.
    private func slowTrace() -> PoseTrace {
        let samples = (0..<3).map { index in
            PoseSample(timestamp: Double(index) * 3600, pose: makePose(yaw: Double(index), pitch: 0))
        }
        return PoseTrace(segments: [TraceSegment(displayID: nil, round: 0, samples: samples)])
    }

    @Test func emitsLifecycleAndEverySampleInOrderAtSpeedZero() async throws {
        let trace = smallTrace()
        let source = ReplayPoseSource(trace: trace, speed: 0)
        let events = await collect(try await source.start(PoseSourceConfiguration()))

        let expectedSamples: [PoseSourceEvent] = trace.segments.flatMap(\.samples).map { .sample($0) }
        let opening: [PoseSourceEvent] = [.status(.starting), .status(.running(nil))]
        let closing: [PoseSourceEvent] = [.status(.stopped)]
        #expect(expectedSamples.count == 18)  // 2 rounds x 2 displays x 4 samples + 2 unlabeled
        let expected: [PoseSourceEvent] = opening + expectedSamples + closing
        #expect(events == expected)
    }

    @Test func negativeSpeedAlsoMeansNoDelay() async throws {
        let source = ReplayPoseSource(trace: slowTrace(), speed: -1)
        let events = await collect(try await source.start(PoseSourceConfiguration()))
        #expect(events.count == 2 + 3 + 1)
        #expect(events.last == .status(.stopped))
    }

    @Test func emptyTraceEmitsOnlyLifecycleEvents() async throws {
        let source = ReplayPoseSource(trace: PoseTrace(), speed: 0)
        let events = await collect(try await source.start(PoseSourceConfiguration()))
        #expect(events == [.status(.starting), .status(.running(nil)), .status(.stopped)])
    }

    @Test func stopFinishesTheStreamWithStoppedAndNoFurtherSamples() async throws {
        let source = ReplayPoseSource(trace: slowTrace(), speed: 1)
        let stream = try await source.start(PoseSourceConfiguration())
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .status(.starting))
        #expect(await iterator.next() == .status(.running(nil)))
        guard case .sample = await iterator.next() else {
            Issue.record("Expected the first sample")
            return
        }
        // The replay is now waiting an hour for the second sample.
        #expect(source.isRunning)
        await source.stop()
        #expect(!source.isRunning)
        #expect(await iterator.next() == .status(.stopped))
        #expect(await iterator.next() == nil)
    }

    @Test func stopIsIdempotentAndSafeWithoutStart() async throws {
        let source = ReplayPoseSource(trace: smallTrace(), speed: 0)
        await source.stop()  // never started

        let events = await collect(try await source.start(PoseSourceConfiguration()))
        #expect(events.last == .status(.stopped))
        await source.stop()  // already finished
        await source.stop()
        #expect(!source.isRunning)
    }

    @Test func startingAgainFinishesThePreviousStreamAndBeginsANewOne() async throws {
        let source = ReplayPoseSource(trace: slowTrace(), speed: 1)
        let first = try await source.start(PoseSourceConfiguration())
        var firstIterator = first.makeAsyncIterator()
        #expect(await firstIterator.next() == .status(.starting))

        let second = try await source.start(PoseSourceConfiguration())

        // The first stream drains its queued events, then reports stopped and finishes.
        var firstRest: [PoseSourceEvent] = []
        while let event = await firstIterator.next() { firstRest.append(event) }
        #expect(firstRest.last == .status(.stopped))
        #expect(firstRest.filter { $0 == .status(.stopped) }.count == 1)

        var secondIterator = second.makeAsyncIterator()
        #expect(await secondIterator.next() == .status(.starting))
        #expect(await secondIterator.next() == .status(.running(nil)))
        #expect(source.isRunning)

        await source.stop()
        var secondRest: [PoseSourceEvent] = []
        while let event = await secondIterator.next() { secondRest.append(event) }
        #expect(secondRest.last == .status(.stopped))
    }

    @Test func aFinishedReplayDoesNotLeaveARunBehind() async throws {
        let source = ReplayPoseSource(trace: PoseTrace(), speed: 0)
        for _ in 0..<20 {
            // The run can finish before start() even returns; it must still end up unregistered.
            _ = await collect(try await source.start(PoseSourceConfiguration()))
        }
        for _ in 0..<100 where source.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!source.isRunning)
    }

    @Test func restartingAfterCompletionReplaysFromTheBeginning() async throws {
        let trace = smallTrace()
        let source = ReplayPoseSource(trace: trace, speed: 0)
        let first = await collect(try await source.start(PoseSourceConfiguration()))
        let second = await collect(try await source.start(PoseSourceConfiguration()))
        #expect(first == second)
    }

    @Test func realTimeReplayWaitsForTimestampDeltas() async throws {
        let samples = (0..<3).map { index in
            PoseSample(timestamp: 10 + Double(index) * 0.05, pose: nil)
        }
        let trace = PoseTrace(segments: [TraceSegment(displayID: nil, round: 0, samples: samples)])
        let source = ReplayPoseSource(trace: trace, speed: 1)
        let clock = ContinuousClock()
        let start = clock.now
        let events = await collect(try await source.start(PoseSourceConfiguration()))
        let elapsed = start.duration(to: clock.now)
        #expect(events.count == 6)
        // Two 50 ms gaps; allow a little slack below the nominal 100 ms.
        #expect(elapsed >= .milliseconds(90))
    }

    @Test func fasterSpeedShortensTheWait() async throws {
        let samples = (0..<3).map { index in PoseSample(timestamp: Double(index) * 600, pose: nil) }
        let trace = PoseTrace(segments: [TraceSegment(displayID: nil, round: 0, samples: samples)])
        let source = ReplayPoseSource(trace: trace, speed: 60_000)  // 20 minutes of data in about 20 ms
        let events = await collect(try await source.start(PoseSourceConfiguration()))
        #expect(events.count == 6)
    }

    @Test func cancellingTheConsumerStopsTheReplay() async throws {
        let source = ReplayPoseSource(trace: slowTrace(), speed: 1)
        let stream = try await source.start(PoseSourceConfiguration())
        let consumer = Task {
            for await _ in stream {}
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(source.isRunning)
        consumer.cancel()
        await consumer.value
        // Terminating the stream cancels the replay task; give it a moment to unwind.
        for _ in 0..<100 where source.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!source.isRunning)
    }
}
