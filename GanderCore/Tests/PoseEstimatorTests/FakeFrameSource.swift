import Foundation
import GanderModels
import Testing
import os

/// A scripted `FrameSource`. Tests drive it by hand with `emitFrame` and `emitStatus`; it never touches a real
/// camera or asks for permission.
final class FakeFrameSource: FrameSource {
    struct State: Sendable {
        var authorization: CameraAuthorization = .authorized
        var startError: (any Error)?
        /// Statuses reported to the status handler from inside `start`, before it returns or throws, the way
        /// `CameraCaptureService` reports `.starting`, `.running`, or `.failed` while it builds the session.
        var statusesDuringStart: [CaptureStatus] = []
        var emitsStoppedOnStop = false
        var startCount = 0
        var stopCount = 0
        var lastDeviceID: String?
        var lastFrameRate: Double?
        var frameHandler: (@Sendable (CameraFrame) -> Void)?
        var statusHandler: (@Sendable (CaptureStatus) -> Void)?
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    /// One blank frame whose buffer is shared by every emitted frame; frames differ only in timestamp.
    private let template = TestPixelBuffer.frame(timestamp: 0)

    init(authorization: CameraAuthorization = .authorized) {
        state.withLock { $0.authorization = authorization }
    }

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var lastDeviceID: String? { state.withLock { $0.lastDeviceID } }
    var lastFrameRate: Double? { state.withLock { $0.lastFrameRate } }
    var frameHandler: (@Sendable (CameraFrame) -> Void)? { state.withLock { $0.frameHandler } }

    func authorizationStatus() -> CameraAuthorization {
        state.withLock { $0.authorization }
    }

    func requestAuthorization() async -> CameraAuthorization {
        Issue.record("Tests must never request camera permission")
        return state.withLock { $0.authorization }
    }

    func availableDevices() -> [CameraDevice] { [] }

    func start(
        deviceID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {
        let (error, statuses) = state.withLock { state -> ((any Error)?, [CaptureStatus]) in
            state.startCount += 1
            state.lastDeviceID = deviceID
            state.lastFrameRate = frameRate
            if state.startError == nil {
                state.frameHandler = frameHandler
                state.statusHandler = statusHandler
            }
            return (state.startError, state.statusesDuringStart)
        }
        for status in statuses { statusHandler(status) }
        if let error { throw error }
    }

    func stop() async {
        let handler = state.withLock { state -> (@Sendable (CaptureStatus) -> Void)? in
            state.stopCount += 1
            defer {
                state.frameHandler = nil
                state.statusHandler = nil
            }
            return state.emitsStoppedOnStop ? state.statusHandler : nil
        }
        handler?(.stopped)
    }

    /// Delivers a frame to the current frame handler, the way the capture queue would.
    func emitFrame(timestamp: TimeInterval) {
        let handler = state.withLock { $0.frameHandler }
        handler?(CameraFrame(pixelBuffer: template.pixelBuffer, timestamp: timestamp))
    }

    /// Delivers a status to the current status handler.
    func emitStatus(_ status: CaptureStatus) {
        let handler = state.withLock { $0.statusHandler }
        handler?(status)
    }
}
