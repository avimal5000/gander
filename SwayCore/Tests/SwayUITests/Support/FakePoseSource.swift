import Foundation
import SwayModels
import os

/// A pose source whose event stream the test controls.
final class FakePoseSource: PoseSource {
    struct State: Sendable {
        var continuation: AsyncStream<PoseSourceEvent>.Continuation?
        var configurations: [PoseSourceConfiguration] = []
        var startError: CameraError?
        var stopCount = 0
        /// When set, `start` immediately yields `.starting` and then `.running(device)`.
        var autoRunDevice: CameraDevice?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(autoRunDevice: CameraDevice? = nil) {
        state.withLock { $0.autoRunDevice = autoRunDevice }
    }

    var configurations: [PoseSourceConfiguration] { state.withLock { $0.configurations } }
    var startCount: Int { configurations.count }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var isStreaming: Bool { state.withLock { $0.continuation != nil } }

    func setStartError(_ error: CameraError?) {
        state.withLock { $0.startError = error }
    }

    func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        let error = state.withLock { state -> CameraError? in
            state.configurations.append(configuration)
            return state.startError
        }
        if let error { throw error }
        let (stream, continuation) = AsyncStream<PoseSourceEvent>.makeStream()
        let device = state.withLock { state -> CameraDevice? in
            state.continuation?.finish()
            state.continuation = continuation
            guard let fallback = state.autoRunDevice else { return nil }
            // Run the camera that was asked for when it is a known one, as the real source does.
            let known = [Fixtures.builtInCamera, Fixtures.externalCamera]
            return known.first { $0.id == configuration.cameraDeviceID } ?? fallback
        }
        if let device {
            continuation.yield(.status(.starting))
            continuation.yield(.status(.running(device)))
        }
        return stream
    }

    func stop() async {
        let continuation = state.withLock { state -> AsyncStream<PoseSourceEvent>.Continuation? in
            state.stopCount += 1
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.yield(.status(.stopped))
        continuation?.finish()
    }

    /// Pushes an event into the current stream.
    func emit(_ event: PoseSourceEvent) {
        _ = state.withLock { $0.continuation }?.yield(event)
    }

    /// Ends the stream without a `stop()` call, as a crashing source would.
    func finishStream() {
        state.withLock { state in
            state.continuation?.finish()
            state.continuation = nil
        }
    }
}
