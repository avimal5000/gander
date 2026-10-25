import CoreVideo
import Foundation

/// A video capture device as seen by Sway.
public struct CameraDevice: Sendable, Hashable, Codable, Identifiable {
    /// `AVCaptureDevice.uniqueID`.
    public var id: String
    /// `AVCaptureDevice.localizedName`.
    public var name: String
    /// True for the Mac's built-in camera (`AVCaptureDevice.DeviceType.builtInWideAngleCamera`).
    public var isBuiltIn: Bool

    public init(id: String, name: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

/// Camera permission state (mirrors `AVAuthorizationStatus`).
public enum CameraAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Reasons capture cannot start or continue.
public enum CameraError: Error, Sendable, Equatable {
    /// Camera permission is not granted.
    case notAuthorized
    /// No video capture device exists.
    case noDevice
    /// The device exists but cannot be used right now (in use by another app, disconnected).
    case deviceUnavailable(String)
    /// The capture session could not be configured.
    case configurationFailed(String)
    /// The running session reported a runtime error.
    case runtimeFailure(String)
}

/// Why capture was suspended by the system. Capture resumes automatically when the condition ends.
public enum SuspendReason: Sendable, Equatable {
    case systemSleep
    case displaysAsleep
    case screenLocked
}

/// Lifecycle state of a frame or pose source.
public enum CaptureStatus: Sendable, Equatable {
    /// Not capturing. Camera indicator off.
    case stopped
    /// Start requested, session configuring.
    case starting
    /// Producing frames. Carries the device in use; `nil` for non-camera sources (replay, synthetic).
    case running(CameraDevice?)
    /// Camera torn down because of sleep/lock; resumes automatically. Camera indicator off.
    case suspended(SuspendReason)
    /// Camera taken away or disconnected mid-run; the source waits and recovers if it can.
    case interrupted(String)
    /// Capture failed and stopped.
    case failed(CameraError)
}

/// A captured video frame. The pixel buffer is only guaranteed valid during the frame handler call.
public struct CameraFrame: @unchecked Sendable {
    // @unchecked: CVPixelBuffer is an immutable-by-convention CF type; frames are consumed
    // synchronously on the capture queue and never mutated.
    public let pixelBuffer: CVPixelBuffer
    /// Seconds on a monotonic clock (sample buffer presentation time).
    public let timestamp: TimeInterval

    public init(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
    }
}

/// Produces raw camera frames. Implemented by `CameraService.CameraCaptureService`.
public protocol FrameSource: AnyObject, Sendable {
    /// Current camera permission state. Never prompts.
    func authorizationStatus() -> CameraAuthorization
    /// Prompts for camera permission if not determined; returns the resulting state.
    func requestAuthorization() async -> CameraAuthorization
    /// Video devices currently connected.
    func availableDevices() -> [CameraDevice]
    /// The device `start(deviceID:)` would capture from right now, or `nil` when there is none. Never touches the
    /// camera or prompts.
    func resolvedDevice(for deviceID: String?) -> CameraDevice?
    /// Starts capture (about 640x480, `frameRate` fps, late frames dropped).
    ///
    /// - Parameters:
    ///   - deviceID: preferred device; `nil` or an unknown ID selects the built-in camera,
    ///     else the system default.
    ///   - frameHandler: called on a private serial queue for every frame.
    ///   - statusHandler: called on any queue for every status change.
    /// - Throws: `CameraError` if capture cannot start. Never prompts for permission.
    /// Calling `start` while running restarts with the new parameters.
    func start(
        deviceID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws
    /// Stops capture and tears down the session so the camera indicator turns off. Idempotent.
    func stop() async
}

extension FrameSource {
    /// For fakes and previews: the device with `deviceID` if listed, else the first built-in, else the first listed.
    /// The real service applies capture's own rule, which ends with the system default instead.
    public func resolvedDevice(for deviceID: String?) -> CameraDevice? {
        let devices = availableDevices()
        return devices.first { $0.id == deviceID } ?? devices.first(where: \.isBuiltIn) ?? devices.first
    }
}
