import Foundation
import GanderModels
import os

/// A pose source whose event stream the test controls.
final class FakePoseSource: PoseSource {
    /// One `setDemand` call and how many starts had happened by then.
    struct DemandCall: Sendable, Equatable {
        var demand: PoseDemand
        var startsSoFar: Int
    }

    struct State: Sendable {
        var continuation: AsyncStream<PoseSourceEvent>.Continuation?
        var configurations: [PoseSourceConfiguration] = []
        var startError: CameraError?
        /// Errors the next starts throw, one each, oldest first; after them starts succeed again.
        var queuedStartErrors: [CameraError] = []
        var stopCount = 0
        var demandCalls: [DemandCall] = []
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
    var demandCalls: [DemandCall] { state.withLock { $0.demandCalls } }
    /// The demand of every call, oldest first.
    var demands: [PoseDemand] { demandCalls.map(\.demand) }

    func setStartError(_ error: CameraError?) {
        state.withLock { $0.startError = error }
    }

    /// Makes the next `errors.count` starts throw those errors in order; starts after them succeed.
    func failNextStarts(with errors: [CameraError]) {
        state.withLock { $0.queuedStartErrors = errors }
    }

    func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        let error = state.withLock { state -> CameraError? in
            state.configurations.append(configuration)
            if let error = state.startError { return error }
            return state.queuedStartErrors.isEmpty ? nil : state.queuedStartErrors.removeFirst()
        }
        if let error { throw error }
        let (stream, continuation) = AsyncStream<PoseSourceEvent>.makeStream()
        let device = state.withLock { state -> CameraDevice? in
            state.continuation?.finish()
            state.continuation = continuation
            guard let fallback = state.autoRunDevice else { return nil }
            // Run the camera that was asked for when it is a known one, as the real source does.
            let known = [Fixtures.builtInCamera, Fixtures.externalCamera, Fixtures.secondExternalCamera]
            return known.first { $0.id == configuration.cameraDeviceID } ?? fallback
        }
        if let device {
            continuation.yield(.status(.starting))
            continuation.yield(.status(.running(device)))
        }
        return stream
    }

    func setDemand(_ demand: PoseDemand) {
        state.withLock { $0.demandCalls.append(DemandCall(demand: demand, startsSoFar: $0.configurations.count)) }
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
