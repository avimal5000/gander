import AVFoundation
import SwayModels

/// AVFoundation camera capture: device selection, permission, a 640x480 video-data session, and recovery.
///
/// The camera session exists only between `start` and `stop`, and it is torn down completely (camera light
/// off) while the system sleeps, the displays sleep, or the screen is locked. Frames are delivered to the
/// frame handler one at a time and are never copied, stored, or written anywhere.
///
/// The type is `Sendable` without `@unchecked`: its only stored property is an immutable reference to the
/// session controller, which confines all mutable state to one serial queue.
public final class CameraCaptureService: FrameSource {
    private let controller = CaptureSessionController()

    /// Creates an idle service. Nothing touches the camera until `start`.
    public init() {}

    /// Current camera permission state. Never prompts.
    public func authorizationStatus() -> CameraAuthorization {
        CameraDeviceCatalog.authorizationStatus()
    }

    /// Asks for camera permission only when it is undetermined, then returns the resulting state.
    public func requestAuthorization() async -> CameraAuthorization {
        let current = CameraDeviceCatalog.authorizationStatus()
        guard current == .notDetermined else { return current }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return CameraDeviceCatalog.authorizationStatus()
    }

    /// Video devices currently connected (built-in, external, and Continuity Camera).
    public func availableDevices() -> [CameraDevice] {
        CameraDeviceCatalog.connectedDevices()
    }

    /// The device `start(deviceID:)` would pick right now, by the same rule (`CameraDeviceSelector`).
    public func resolvedDevice(for deviceID: String?) -> CameraDevice? {
        try? CameraDeviceSelector.select(
            preferredID: deviceID,
            devices: CameraDeviceCatalog.connectedDevices(),
            systemDefault: CameraDeviceCatalog.systemDefault()
        ).device
    }

    /// Starts capture, or restarts it with the new parameters if it is already running.
    ///
    /// Never prompts for permission. Throws `CameraError.notAuthorized` unless access is already granted,
    /// `CameraError.noDevice` when no camera exists, and `deviceUnavailable` or `configurationFailed` when
    /// the session cannot be built. An unknown `deviceID` silently falls back to the built-in camera.
    public func start(
        deviceID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {
        try await controller.start(
            preferredID: deviceID,
            frameRate: frameRate,
            frameHandler: frameHandler,
            statusHandler: statusHandler
        )
    }

    /// Stops capture and tears the session down so the camera light turns off. Safe to call repeatedly.
    public func stop() async {
        await controller.stop()
    }
}
