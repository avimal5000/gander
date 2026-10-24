import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The CameraService builder replaces this file. See CONTRACT.md.

/// AVFoundation camera capture.
public final class CameraCaptureService: FrameSource {
    public init() {}

    public func authorizationStatus() -> CameraAuthorization { .notDetermined }

    public func requestAuthorization() async -> CameraAuthorization { .notDetermined }

    public func availableDevices() -> [CameraDevice] { [] }

    public func start(
        deviceID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {
        throw CameraError.noDevice
    }

    public func stop() async {}
}
