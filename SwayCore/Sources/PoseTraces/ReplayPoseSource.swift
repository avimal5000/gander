import Foundation
import SwayModels
import os

/// A `PoseSource` that replays the samples of a recorded trace, paced by their timestamps.
///
/// Event order: `.status(.starting)`, `.status(.running(nil))`, every sample of every segment in array order,
/// `.status(.stopped)`, then the stream finishes. Use it to re-run analysis or the debug UI without a camera.
public final class ReplayPoseSource: PoseSource {
    /// A replay run in progress.
    private struct Run: Sendable {
        let id: UInt64
        let task: Task<Void, Never>
    }

    private struct State: Sendable {
        var nextRunID: UInt64 = 0
        var run: Run?
    }

    private let samples: [PoseSample]
    private let speed: Double
    // The only mutable state; guarded by the lock.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Creates a replay source.
    /// - Parameters:
    ///   - trace: the trace to replay; unlabeled and labeled segments are both replayed.
    ///   - speed: playback speed multiplier (2 = twice as fast). `speed <= 0` replays with no delay.
    public init(trace: PoseTrace, speed: Double = 1.0) {
        self.samples = trace.segments.flatMap(\.samples)
        self.speed = speed
    }

    /// Starts a replay and returns its event stream. If a replay is already running it is stopped first, and its
    /// stream emits `.status(.stopped)` and finishes. Never throws.
    public func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        let (stream, continuation) = AsyncStream<PoseSourceEvent>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(.status(.starting))
        continuation.yield(.status(.running(nil)))

        let samples = self.samples
        let speed = self.speed
        let state = self.state
        // The new run is registered and its task created inside one critical section. The task's cleanup takes
        // the same lock, so a run that finishes immediately can never be registered after it has been cleaned up.
        let previous = state.withLock { current -> Run? in
            current.nextRunID &+= 1
            let runID = current.nextRunID
            let task = Task {
                await Self.replay(samples: samples, speed: speed, into: continuation)
                state.withLock { current in
                    if current.run?.id == runID { current.run = nil }
                }
            }
            // If the consumer stops iterating, stop producing.
            continuation.onTermination = { @Sendable _ in task.cancel() }
            let previous = current.run
            current.run = Run(id: runID, task: task)
            return previous
        }
        if let previous {
            previous.task.cancel()
            await previous.task.value
        }
        return stream
    }

    /// Stops the current replay: its stream emits `.status(.stopped)` and finishes before this returns.
    /// Idempotent.
    public func stop() async {
        let run = state.withLock { state -> Run? in
            let run = state.run
            state.run = nil
            return run
        }
        guard let run else { return }
        run.task.cancel()
        await run.task.value
    }

    // MARK: - Internals

    /// True while a replay is producing events.
    var isRunning: Bool {
        state.withLock { $0.run != nil }
    }

    /// Yields every sample, sleeping between samples so that elapsed replay time equals the sum of positive
    /// timestamp deltas divided by `speed`. On cancellation or completion it yields `.stopped` and finishes the
    /// stream. This is the only place that yields after startup, so event order is always preserved.
    private static func replay(
        samples: [PoseSample],
        speed: Double,
        into continuation: AsyncStream<PoseSourceEvent>.Continuation
    ) async {
        let clock = ContinuousClock()
        let origin = clock.now
        var previousTimestamp: TimeInterval?
        var scheduledSeconds = 0.0

        for sample in samples {
            if Task.isCancelled { break }
            if let previousTimestamp {
                scheduledSeconds += max(0, sample.timestamp - previousTimestamp)
            }
            previousTimestamp = sample.timestamp
            if speed > 0 {
                // Deadline-based (not accumulated sleeps) so scheduling jitter does not drift.
                let offset = min(scheduledSeconds / speed, maxOffsetSeconds)
                let deadline = origin.advanced(by: .seconds(offset))
                if deadline > clock.now {
                    do {
                        try await clock.sleep(until: deadline)
                    } catch {
                        break
                    }
                }
            }
            continuation.yield(.sample(sample))
        }
        continuation.yield(.status(.stopped))
        continuation.finish()
    }

    /// Upper bound on a single scheduled offset; protects `Duration` from absurdly small speeds.
    private static let maxOffsetSeconds = 10_000_000.0
}
