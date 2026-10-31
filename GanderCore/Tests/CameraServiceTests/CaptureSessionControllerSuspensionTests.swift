import Foundation
import GanderModels
import Testing
import os

@testable import CameraService

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

    @Test func aSessionStartedInTheBackgroundKeepsTheFirstStartSuspended() async throws {
        let harness = ControllerHarness(sessionInactive: true)
        try await harness.start()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.sessionInactive), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func theSeededSessionReasonEndsWhenTheSessionBecomesActive() async throws {
        let harness = ControllerHarness(sessionInactive: true)
        harness.lockScreen()
        try await harness.start()
        harness.returnToSession()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.sessionInactive), .suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }

    @Test func bothSeedsApplyTogetherAndTheDisplayOneIsReportedFirst() async throws {
        let harness = ControllerHarness(displayAsleep: true, sessionInactive: true)
        try await harness.start()
        harness.returnToSession()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.displaysAsleep), .stopped])
    }

    @Test func lockAndUnlockAreObservedThroughTheInjectedDistributedRegistration() {
        let harness = ControllerHarness()
        let names = harness.distributedRegistrations.withLock { $0 }
        #expect(
            names == [Notification.Name("com.apple.screenIsLocked"), Notification.Name("com.apple.screenIsUnlocked")])
    }

    @Test func aControllerIsReleasedWithItsObservers() async throws {
        weak var released: CaptureSessionController?
        var registrations: OSAllocatedUnfairLock<[Notification.Name]>?
        do {
            let harness = ControllerHarness()
            released = harness.controller
            registrations = harness.distributedRegistrations
            #expect(harness.distributedRegistrations.withLock { $0.count } == 2)
            harness.lockScreen()
            try await harness.start()
            await harness.controller.stop()
        }
        // The last queued block drops its reference just after `stop` returns; give it a moment.
        for _ in 0..<100 where released != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(released == nil)
        // `deinit` removed the distributed registrations too.
        #expect(registrations?.withLock { $0.isEmpty } == true)
    }
}
