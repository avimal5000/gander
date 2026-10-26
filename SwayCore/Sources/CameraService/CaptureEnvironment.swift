import AVFoundation
import AppKit
import SwayModels

/// Everything `CaptureSessionController` reads from or changes in the system, apart from the capture session
/// itself. The live values talk to AVFoundation, the displays, and the real notification centers; tests inject
/// fakes, so they never touch a camera, a display, or a system notification (CONTRACT 12).
struct CaptureEnvironment: Sendable {
    var authorizationStatus: @Sendable () -> CameraAuthorization
    var connectedDevices: @Sendable () -> [CameraDevice]
    var systemDefaultDevice: @Sendable () -> CameraDevice?
    var isDeviceConnected: @Sendable (String) -> Bool
    /// True when the main display is asleep. Seeds `.displaysAsleep` and heals a missed display wake (D43).
    var isMainDisplayAsleep: @Sendable () -> Bool
    /// Turns Center Stage off for Sway's own capture (D47). Called before every session build; the live function
    /// does its work once per process.
    var turnCenterStageOff: @Sendable () -> Void
    /// Posts sleep, display sleep, and user-session notifications (`NSWorkspace`'s center).
    var workspaceCenter: NotificationCenter
    /// Posts the screen lock and unlock notifications (the distributed center).
    var distributedCenter: NotificationCenter
    /// Posts camera connect and disconnect notifications.
    var deviceCenter: NotificationCenter

    static var live: CaptureEnvironment {
        CaptureEnvironment(
            authorizationStatus: { CameraDeviceCatalog.authorizationStatus() },
            connectedDevices: { CameraDeviceCatalog.connectedDevices() },
            systemDefaultDevice: { CameraDeviceCatalog.systemDefault() },
            isDeviceConnected: { CameraDeviceCatalog.isConnected(id: $0) },
            isMainDisplayAsleep: { CGDisplayIsAsleep(CGMainDisplayID()) != 0 },
            turnCenterStageOff: { CenterStageControl.turnOffOnce() },
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            distributedCenter: DistributedNotificationCenter.default(),
            deviceCenter: .default
        )
    }
}
