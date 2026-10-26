import AppKit
import SwayModels
import Testing
import os

@testable import CameraService

/// A real `CaptureSessionController` wired to fake notification centers and fake system queries, so the tests send
/// "system" notifications without touching a camera, a display, or the real notification centers (CONTRACT 12).
///
/// Every scenario here keeps at least one suspend reason active whenever it calls `start`, so no test ever reaches the
/// code that opens AVFoundation. `centerStageCalls` proves it: the session builder calls it first.
private final class ControllerHarness: Sendable {
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let devices = NotificationCenter()
    let controller: CaptureSessionController

    private let displayAsleep: OSAllocatedUnfairLock<Bool>
    private let centerStageTurnedOff = OSAllocatedUnfairLock(initialState: 0)
    private let recordedStatuses = OSAllocatedUnfairLock(initialState: [CaptureStatus]())

    init(displayAsleep initiallyAsleep: Bool = false) {
        let workspace = workspace
        let distributed = distributed
        let devices = devices
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
                turnCenterStageOff: { turnedOff.withLock { $0 += 1 } },
                workspaceCenter: workspace,
                distributedCenter: distributed,
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

@Suite("Capture session controller suspension")
struct CaptureSessionControllerSuspensionTests {
    @Test func startingWhileLockedKeepsTheCameraOff() async throws {
        let harness = ControllerHarness()
        harness.lockScreen()
        try await harness.start()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    /// The audit finding: stop forgot the lock, and the next start turned the camera on at the lock screen.
    @Test func startStopStartWhileLockedStaysSuspended() async throws {
        let harness = ControllerHarness()
        harness.lockScreen()
        try await harness.start()
        await harness.controller.stop()
        try await harness.start()
        await harness.controller.stop()
        #expect(
            harness.statuses == [.suspended(.screenLocked), .stopped, .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func stoppingTwiceDoesNotForgetTheLock() async throws {
        let harness = ControllerHarness()
        harness.lockScreen()
        try await harness.start()
        await harness.controller.stop()
        await harness.controller.stop()
        try await harness.start()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.screenLocked), .stopped, .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func restartingWhileLockedStaysSuspended() async throws {
        let harness = ControllerHarness()
        harness.lockScreen()
        try await harness.start()
        try await harness.start()
        await harness.controller.stop()
        #expect(
            harness.statuses == [.suspended(.screenLocked), .stopped, .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func eventsWhileStoppedAreTrackedByTheObserversThatStayInstalled() async throws {
        let harness = ControllerHarness()
        harness.sleepSystem()
        try await harness.start()
        await harness.controller.stop()
        // Both happen with capture stopped: the lock begins, and the wake clears the sleep.
        harness.lockScreen()
        harness.wakeSystem()
        try await harness.start()
        await harness.controller.stop()
        #expect(
            harness.statuses == [.suspended(.systemSleep), .stopped, .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func aDisplayAsleepAtLaunchKeepsTheFirstStartSuspended() async throws {
        let harness = ControllerHarness(displayAsleep: true)
        try await harness.start()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.displaysAsleep), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func anotherUsersSessionSuspendsUntilThisOneReturns() async throws {
        let harness = ControllerHarness()
        harness.leaveSession()
        harness.lockScreen()
        try await harness.start()
        harness.returnToSession()
        await harness.controller.stop()
        #expect(
            harness.statuses == [.suspended(.sessionInactive), .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func aWakeHealsAMissedDisplayWake() async throws {
        let harness = ControllerHarness()
        harness.sleepDisplays()
        harness.lockScreen()
        try await harness.start()
        // The `screensDidWake` never arrived, but the display is awake when the Mac wakes from sleep.
        harness.setDisplayAsleep(false)
        harness.wakeSystem()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.displaysAsleep), .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func aWakeDoesNotHealWhileTheDisplayIsStillAsleep() async throws {
        let harness = ControllerHarness()
        harness.sleepSystem()
        harness.sleepDisplays()
        harness.setDisplayAsleep(true)
        try await harness.start()
        harness.wakeSystem()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.systemSleep), .suspended(.displaysAsleep), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func theSeededDisplaySleepHealsLikeAnyOther() async throws {
        let harness = ControllerHarness(displayAsleep: true)
        harness.leaveSession()
        try await harness.start()
        harness.setDisplayAsleep(false)
        harness.unlockScreen()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.displaysAsleep), .suspended(.sessionInactive), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func aDisplayWakeThatArrivesOnTimeEndsTheReasonWithoutHealing() async throws {
        let harness = ControllerHarness()
        harness.sleepDisplays()
        harness.lockScreen()
        try await harness.start()
        harness.wakeDisplays()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.displaysAsleep), .suspended(.screenLocked), .stopped])
    }

    @Test func aControllerIsReleasedWithItsObservers() async throws {
        weak var released: CaptureSessionController?
        do {
            let harness = ControllerHarness()
            released = harness.controller
            harness.lockScreen()
            try await harness.start()
            await harness.controller.stop()
        }
        // The last queued block drops its reference just after `stop` returns; give it a moment.
        for _ in 0..<100 where released != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(released == nil)
    }
}
