import Foundation
import GanderModels
import os

/// A camera that never touches hardware or permission APIs.
final class FakeFrameSource: FrameSource {
    struct State: Sendable {
        var authorization: CameraAuthorization
        var authorizationAfterRequest: CameraAuthorization = .authorized
        var devices: [CameraDevice] = []
        /// What capture opens when no listed device matches the request; `nil` uses the protocol's default rule.
        var fallbackDevice: CameraDevice?
        var requestCount = 0
        var stopCount = 0
        var deviceListCalls = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(
        authorization: CameraAuthorization = .authorized, devices: [CameraDevice] = [],
        fallbackDevice: CameraDevice? = nil
    ) {
        state = OSAllocatedUnfairLock(
            initialState: State(authorization: authorization, devices: devices, fallbackDevice: fallbackDevice))
    }

    var requestCount: Int { state.withLock { $0.requestCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    /// How many times the device list was read (`availableDevices()`).
    var deviceListCalls: Int { state.withLock { $0.deviceListCalls } }

    func setAuthorization(_ value: CameraAuthorization) {
        state.withLock { $0.authorization = value }
    }

    func setAuthorizationAfterRequest(_ value: CameraAuthorization) {
        state.withLock { $0.authorizationAfterRequest = value }
    }

    func setDevices(_ devices: [CameraDevice]) {
        state.withLock { $0.devices = devices }
    }

    func authorizationStatus() -> CameraAuthorization {
        state.withLock { $0.authorization }
    }

    func requestAuthorization() async -> CameraAuthorization {
        state.withLock {
            $0.requestCount += 1
            $0.authorization = $0.authorizationAfterRequest
            return $0.authorization
        }
    }

    func availableDevices() -> [CameraDevice] {
        state.withLock {
            $0.deviceListCalls += 1
            return $0.devices
        }
    }

    func resolvedDevice(for deviceID: String?) -> CameraDevice? {
        let (devices, fallback) = state.withLock { ($0.devices, $0.fallbackDevice) }
        if let match = devices.first(where: { $0.id == deviceID }) { return match }
        return fallback ?? devices.first(where: \.isBuiltIn) ?? devices.first
    }

    func start(
        deviceID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {}

    func stop() async {
        state.withLock { $0.stopCount += 1 }
    }
}
