import AVFoundation
import SwayModels

/// Thin wrapper over the AVFoundation queries the service needs (discovery, default device, permission).
///
/// Everything with a decision in it lives in the pure types; this enum only reads system state. Tests do not
/// call the query functions, because they would touch real devices.
enum CameraDeviceCatalog {
    /// Device types Gander offers (CONTRACT 6.1).
    static var discoveryDeviceTypes: [AVCaptureDevice.DeviceType] {
        [.builtInWideAngleCamera, .external, .continuityCamera]
    }

    /// Video devices currently connected, in discovery order.
    static func connectedDevices() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: discoveryDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices.map(makeDevice)
    }

    /// `AVCaptureDevice.default(for: .video)` as a `CameraDevice`, if there is one.
    static func systemDefault() -> CameraDevice? {
        AVCaptureDevice.default(for: .video).map(makeDevice)
    }

    /// True if a device with this ID is connected now.
    static func isConnected(id: String) -> Bool {
        connectedDevices().contains { $0.id == id } || systemDefault()?.id == id
    }

    /// Current permission state. Never prompts.
    static func authorizationStatus() -> CameraAuthorization {
        CameraAuthorizationMapper.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// `isBuiltIn` rule: the device type is the built-in wide-angle camera.
    ///
    /// Without the `NSCameraUseContinuityCameraDeviceType` Info.plist key, macOS reports a Continuity Camera
    /// (an iPhone) as `.builtInWideAngleCamera`. Those are excluded through `isContinuityCamera` so an
    /// iPhone is never mistaken for the Mac's own camera.
    static func isBuiltIn(deviceType: AVCaptureDevice.DeviceType, isContinuityCamera: Bool) -> Bool {
        deviceType == .builtInWideAngleCamera && !isContinuityCamera
    }

    private static func makeDevice(_ device: AVCaptureDevice) -> CameraDevice {
        CameraDevice(
            id: device.uniqueID,
            name: device.localizedName,
            isBuiltIn: isBuiltIn(deviceType: device.deviceType, isContinuityCamera: device.isContinuityCamera)
        )
    }
}
