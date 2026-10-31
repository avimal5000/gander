import AppKit
import GanderModels
import os

@testable import CameraService

/// A real `CaptureSessionController` wired to fake notification centers and fake system queries, so the tests send
/// "system" notifications without touching a camera, a display, or the real notification centers (CONTRACT 12).
///
/// Every scenario here keeps at least one suspend reason active whenever it calls `start`, so no test ever reaches the
/// code that opens AVFoundation. `sessionBuilds` proves it: the session builder calls it first.
final class ControllerHarness: Sendable {
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let devices = NotificationCenter()
    let controller: CaptureSessionController
    /// The names the controller currently observes through the injected distributed registration, oldest first.
    let distributedRegistrations = OSAllocatedUnfairLock(initialState: [Notification.Name]())

    private let displayAsleep: OSAllocatedUnfairLock<Bool>
    private let centerStageTurnedOff = OSAllocatedUnfairLock(initialState: 0)
    private let recordedStatuses = OSAllocatedUnfairLock(initialState: [CaptureStatus]())

    init(
        displayAsleep initiallyAsleep: Bool = false,
        sessionInactive: Bool = false,
        observeDistributed: DistributedObservation? = nil
    ) {
        let workspace = workspace
        let distributed = distributed
        let devices = devices
        let registrations = distributedRegistrations
        let asleep = OSAllocatedUnfairLock(initialState: initiallyAsleep)
        let turnedOff = centerStageTurnedOff
        let camera = CameraDevice(id: "test-camera", name: "Test camera", isBuiltIn: true)
        displayAsleep = asleep
        controller = CaptureSessionController(
            environment: CaptureEnvironment(
                authorizationStatus: { .authorized },
                connectedDevices: { [camera] },
                systemDefaultDevice: { nil },
                isDeviceConnected: { _ in true },
                isMainDisplayAsleep: { asleep.withLock { $0 } },
                isSessionInactive: { sessionInactive },
                turnCenterStageOff: { turnedOff.withLock { $0 += 1 } },
                workspaceCenter: workspace,
                observeDistributedNotification: observeDistributed ?? { name, handler in
                    // A plain center stands in for the distributed one; the real registration has its own tests.
                    let token = distributed.addObserver(forName: name, object: nil, queue: nil, using: handler)
                    registrations.withLock { $0.append(name) }
                    return {
                        distributed.removeObserver(token)
                        registrations.withLock { names in names.removeAll { $0 == name } }
                    }
                },
                deviceCenter: devices
            )
        )
    }

    var statuses: [CaptureStatus] { recordedStatuses.withLock { $0 } }
    /// How many times a session build began. Zero means no session was ever built.
    var sessionBuilds: Int { centerStageTurnedOff.withLock { $0 } }

    func setDisplayAsleep(_ asleep: Bool) {
        displayAsleep.withLock { $0 = asleep }
    }

    func start() async throws {
        let recorded = recordedStatuses
        try await controller.start(
            preferredID: nil,
            frameRate: 15,
            frameHandler: { _ in },
            statusHandler: { status in recorded.withLock { $0.append(status) } }
        )
    }

    // The posts are synchronous and enqueue their work on the controller's queue ahead of any later `start`/`stop`.
    func sleepSystem() { workspace.post(name: NSWorkspace.willSleepNotification, object: nil) }
    func wakeSystem() { workspace.post(name: NSWorkspace.didWakeNotification, object: nil) }
    func sleepDisplays() { workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil) }
    func wakeDisplays() { workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil) }
    func leaveSession() { workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil) }
    func returnToSession() { workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil) }
    func lockScreen() { distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil) }
    func unlockScreen() { distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil) }
}
