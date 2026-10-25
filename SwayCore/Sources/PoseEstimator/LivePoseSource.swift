import Foundation
import SwayModels
import os

/// Live camera pose source: a `FrameSource` feeding a `PoseEstimating`.
///
/// Each `start` creates one run with its own event stream. Frames are estimated synchronously on the frame
/// source's capture queue and yielded as `.sample` events. Ending the run in any way (`stop`, a second
/// `start`, a start failure, or the consumer abandoning the stream) stops the frame source, so the camera
/// never keeps running without a consumer.
///
/// Statuses are states, so a status equal to the one just reported on the same run is dropped. This removes the
/// echoes that come from layering on a frame source: its own `.starting` right after ours, and the `.failed` it
/// reports just before its `start` throws, which this source then reports too. The stream therefore carries one
/// `.starting` and at most one `.failed` per run.
public final class LivePoseSource: PoseSource {
    /// The mutable run state, guarded by `state`.
    private struct RunState: Sendable {
        /// Incremented whenever a run begins or ends. A handler or termination callback only acts if its
        /// captured value still matches, which retires every handler of a previous run.
        var generation: UInt64 = 0
        /// The active run's continuation; `nil` when not running.
        var continuation: AsyncStream<PoseSourceEvent>.Continuation?
        /// The last status yielded on the active run's stream, for dropping consecutive duplicates.
        var lastStatus: CaptureStatus?
    }

    private let frameSource: any FrameSource
    private let estimator: any PoseEstimating
    private let logger = SwayLog.logger(category: "pose")
    private let state = OSAllocatedUnfairLock(initialState: RunState())
    /// Serializes `start` and `stop` so they never interleave across their suspension points.
    private let gate = AsyncGate()
    /// Test seam: receives each new stream right after creation, before the frame source is started, so a
    /// test can observe events of a run whose `start` throws (the caller never receives that stream).
    private let streamObserver: (@Sendable (AsyncStream<PoseSourceEvent>) -> Void)?

    public convenience init(frameSource: any FrameSource, estimator: any PoseEstimating) {
        self.init(frameSource: frameSource, estimator: estimator, streamObserver: nil)
    }

    init(
        frameSource: any FrameSource,
        estimator: any PoseEstimating,
        streamObserver: (@Sendable (AsyncStream<PoseSourceEvent>) -> Void)?
    ) {
        self.frameSource = frameSource
        self.estimator = estimator
        self.streamObserver = streamObserver
    }

    deinit {
        // Last line of defense: if this object goes away mid-run, still turn the camera off.
        let continuation = state.withLock { state -> AsyncStream<PoseSourceEvent>.Continuation? in
            defer { state.continuation = nil }
            return state.continuation
        }
        guard let continuation else { return }
        continuation.yield(.status(.stopped))
        continuation.finish()
        let frameSource = frameSource
        Task { await frameSource.stop() }
    }

    public func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        await gate.acquire()
        defer { gate.release() }

        if state.withLock({ $0.continuation != nil }) {
            await endRun()
        }
        guard frameSource.authorizationStatus() == .authorized else {
            throw CameraError.notAuthorized
        }

        let (stream, continuation) = AsyncStream<PoseSourceEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let generation = state.withLock { state -> UInt64 in
            state.generation &+= 1
            state.continuation = continuation
            state.lastStatus = .starting
            return state.generation
        }
        continuation.onTermination = { [weak self] _ in
            // Fires for our own finish too, but then the generation is already stale and this does nothing.
            guard let self else { return }
            Task { await self.stopIfCurrent(generation: generation) }
        }
        streamObserver?(stream)
        continuation.yield(.status(.starting))

        let state = state
        let estimator = estimator
        do {
            try await frameSource.start(
                deviceID: configuration.cameraDeviceID,
                frameRate: configuration.frameRate,
                frameHandler: { frame in
                    guard state.withLock({ $0.generation == generation }) else { return }
                    let pose = estimator.estimate(frame, includeLandmarks: configuration.includeLandmarks)
                    continuation.yield(.sample(PoseSample(timestamp: frame.timestamp, pose: pose)))
                },
                statusHandler: { status in
                    Self.yieldStatus(status, generation: generation, state: state, continuation: continuation)
                }
            )
        } catch {
            await failRun(generation: generation, continuation: continuation, error: error)
            throw error
        }
        return stream
    }

    public func stop() async {
        await gate.acquire()
        defer { gate.release() }
        await endRun()
    }

    /// Ends the active run if it is still the run with `generation` (the consumer abandoned its stream).
    private func stopIfCurrent(generation: UInt64) async {
        await gate.acquire()
        defer { gate.release() }
        guard state.withLock({ $0.generation == generation && $0.continuation != nil }) else { return }
        logger.info("Pose stream abandoned by its consumer; stopping capture")
        await endRun()
    }

    /// Yields `status` on the run with `generation` unless that run has ended or just reported the same status.
    ///
    /// The check and the yield happen under the lock so concurrent callers cannot reorder or double-report a
    /// status. `yield` never blocks and never calls back into this type, so holding the lock across it is safe.
    private static func yieldStatus(
        _ status: CaptureStatus,
        generation: UInt64,
        state: OSAllocatedUnfairLock<RunState>,
        continuation: AsyncStream<PoseSourceEvent>.Continuation
    ) {
        state.withLock { state in
            guard state.generation == generation, state.lastStatus != status else { return }
            state.lastStatus = status
            continuation.yield(.status(status))
        }
    }

    /// Ends a run whose frame source failed to start: reports `.failed` (once), finishes the stream, and makes sure
    /// nothing is left capturing. The caller must hold `gate` and rethrow `error`.
    private func failRun(
        generation: UInt64,
        continuation: AsyncStream<PoseSourceEvent>.Continuation,
        error: any Error
    ) async {
        logger.error("Camera start failed: \(String(describing: error), privacy: .public)")
        let failure = (error as? CameraError) ?? .configurationFailed(String(describing: error))
        // Report the failure on the run first (deduplicated against the frame source's own `.failed`), then retire
        // the run so late handler calls are dropped.
        Self.yieldStatus(.failed(failure), generation: generation, state: state, continuation: continuation)
        state.withLock { state in
            state.generation &+= 1
            state.continuation = nil
            state.lastStatus = nil
        }
        continuation.finish()
        // A failed start should leave nothing capturing; stopping is idempotent.
        await frameSource.stop()
    }

    /// Stops capture and finishes the current stream. The caller must hold `gate`.
    ///
    /// The generation moves on first, so frames and statuses still in flight are dropped, including the frame
    /// source's own `.stopped`; this run then reports exactly one `.stopped`. The frame source is stopped even
    /// when no run is active, which is harmless and keeps `stop()` a reliable privacy backstop.
    private func endRun() async {
        let continuation = state.withLock { state -> AsyncStream<PoseSourceEvent>.Continuation? in
            state.generation &+= 1
            state.lastStatus = nil
            defer { state.continuation = nil }
            return state.continuation
        }
        await frameSource.stop()
        continuation?.yield(.status(.stopped))
        continuation?.finish()
    }
}
