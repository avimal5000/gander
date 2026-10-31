import Foundation
import SwayModels
import Testing

@testable import SwayUI

/// CONTRACT 6.5.5 items 4 to 8: only a running camera switches, the camera list is read less often, the camera waits
/// 2 s after a display change, a missing USB camera falls back, and "No face" is steadier.
@MainActor
@Suite("AppModel camera recovery")
struct AppModelCameraRecoveryTests {
    private let right = Fixtures.right.id
    private let connected = Notification.Name("AVCaptureDeviceWasConnectedNotification")
    private let disconnected = Notification.Name("AVCaptureDeviceWasDisconnectedNotification")
    private let builtIn = Fixtures.builtInCamera
    private let external = Fixtures.externalCamera
    private let otherUSB = Fixtures.secondExternalCamera

    /// A calibrated model with Tracking on, the camera reported running, and the first poll done.
    private func trackingHarness() async -> Harness {
        let h = Harness.make(calibrated: true)
        await h.startTracking()
        await h.settlePoll()
        return h
    }

    private func feed(_ h: Harness, at time: TimeInterval, face: Bool = true) {
        h.model.handle(.sample(Fixtures.sample(at: time, face: face)))
    }

    // MARK: Item 4: only a running camera switches

    @Test func onlyARunningCameraSwitches() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(
            .focused(Fixtures.window(7, app: "Safari", on: Fixtures.right), method: .appActivation, milliseconds: 120))
        h.engine.script.set { sample, _ in
            Fixtures.decision(
                switchTo: Fixtures.right.id, phase: .coolingDown(until: sample.timestamp + 0.75),
                classification: Fixtures.classification(best: Fixtures.right.id))
        }
        let recorder = h.engine.lastRecorder

        for status: CaptureStatus in [
            .interrupted("Camera disconnected"), .suspended(.screenLocked), .starting, .stopped,
        ] {
            h.model.handle(.status(status))
            feed(h, at: 1.4)
            #expect(recorder?.samples.isEmpty == true, "\(status) must not feed the decider")
        }
        await h.settleSwitch()
        #expect(h.focus.focusCalls.isEmpty)

        h.model.handle(.status(.running(Fixtures.builtInCamera)))
        feed(h, at: 1.5)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "Running again: the look counts")
    }

    // MARK: Item 5: fewer environment refreshes

    @Test func aBurstOfCameraNotificationsBecomesOneRefreshHalfASecondAfterTheLast() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let reads = h.camera.deviceListCalls

        h.notifications.post(name: connected, object: nil)
        h.scheduler.advance(by: 0.3)
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: 0.3)
        h.notifications.post(name: connected, object: nil)
        #expect(AppModel.environmentRefreshDelay == 0.5)
        h.scheduler.advance(by: 0.49)
        #expect(h.camera.deviceListCalls == reads, "Not read on each notification, nor 0.5 s after the first")

        h.scheduler.advance(by: 0.01)
        #expect(h.camera.deviceListCalls == reads + 1)
        h.scheduler.advance(by: 10)
        #expect(h.camera.deviceListCalls == reads + 1, "One refresh for the whole burst")
    }

    @Test func nothingIsReadWhileTheCameraIsSuspended() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.handle(.status(.suspended(.screenLocked)))
        let reads = h.camera.deviceListCalls

        h.notifications.post(name: connected, object: nil)
        h.notifications.post(name: disconnected, object: nil)

        #expect(!h.scheduler.hasPending, "Nothing is even scheduled")
        h.scheduler.advance(by: 10)
        #expect(h.camera.deviceListCalls == reads)
    }

    @Test func aRefreshWaitingWhenTheCameraSuspendsIsSkipped() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let reads = h.camera.deviceListCalls
        h.notifications.post(name: connected, object: nil)

        h.model.handle(.status(.suspended(.systemSleep)))
        h.scheduler.advance(by: 0.5)

        #expect(h.camera.deviceListCalls == reads)
    }

    @Test func leavingSuspendedReadsTheCameraListOnce() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.handle(.status(.suspended(.screenLocked)))
        h.notifications.post(name: disconnected, object: nil)
        let reads = h.camera.deviceListCalls

        h.model.handle(.status(.suspended(.displaysAsleep)))
        #expect(h.camera.deviceListCalls == reads, "Still suspended")
        h.model.handle(.status(.starting))
        #expect(h.camera.deviceListCalls == reads + 1)
        h.model.handle(.status(.running(builtIn)))
        #expect(h.camera.deviceListCalls == reads + 1, "Once, when the status leaves suspended")
    }

    @Test func windowsStillRefreshAtOnce() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let reads = h.camera.deviceListCalls

        h.model.refreshEnvironment()

        #expect(h.camera.deviceListCalls == reads + 1)
    }

    // MARK: Item 6: the camera waits 2 s after a display change

    private func graceHarness() async -> Harness {
        let h = Harness.make(layout: Fixtures.threeDisplays, autoRun: true, calibrated: true)
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        await h.model.cameraOperation?.value
        return h
    }

    @Test func aDisplayChangeThatLeavesNoCalibrationStopsTheCameraTwoSecondsLater() async {
        let h = await graceHarness()
        defer { h.tearDown() }

        h.model.layoutDidChange(Fixtures.oneDisplay)
        await h.model.cameraOperation?.value
        #expect(h.model.activeCalibration == nil)
        #expect(h.model.isCameraActive)
        #expect(h.pose.stopCount == 0)
        #expect(h.scheduler.pendingDelays == [AppModel.cameraGraceDelay])
        #expect(AppModel.cameraGraceDelay == 2)

        h.scheduler.advance(by: 1.99)
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive, "Not yet")

        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.trackingStatus == .oneDisplay)
    }

    @Test func anUnknownDisplaySetGetsTheSameGrace() async {
        let h = await graceHarness()
        defer { h.tearDown() }

        h.model.layoutDidChange(Fixtures.fourDisplays)
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive)
        #expect(h.model.trackingStatus == .needsCalibration)

        h.scheduler.advance(by: 2)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)
    }

    @Test func aLayoutThatRecoversWithinTheGraceCancelsTheStop() async {
        let h = await graceHarness()
        defer { h.tearDown() }
        h.model.layoutDidChange(Fixtures.oneDisplay)
        await h.model.cameraOperation?.value
        h.scheduler.advance(by: 1.5)

        h.model.layoutDidChange(Fixtures.threeDisplays)
        await h.model.cameraOperation?.value

        #expect(!h.scheduler.hasPending, "The stop is cancelled")
        h.scheduler.advance(by: 10)
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive)
        #expect(h.pose.stopCount == 0)
        #expect(h.pose.startCount == 1, "The camera never blinked")
        #expect(h.model.activeCalibration != nil)
    }

    @Test func noSwitchingHappensDuringTheGrace() async {
        let h = await graceHarness()
        defer { h.tearDown() }
        h.model.layoutDidChange(Fixtures.oneDisplay)
        await h.model.cameraOperation?.value
        let count = h.engine.lastRecorder?.samples.count

        h.run(frames: 10, dt: 0.1)
        await h.settleSwitch()

        #expect(h.model.isCameraActive)
        #expect(h.engine.lastRecorder?.samples.count == count, "Nothing is calibrated, so the decider sees nothing")
        #expect(h.focus.focusCalls.isEmpty)
    }

    @Test func aSecondDisplayChangeDoesNotExtendTheGrace() async {
        let h = await graceHarness()
        defer { h.tearDown() }
        h.model.layoutDidChange(Fixtures.oneDisplay)
        h.scheduler.advance(by: 1)

        h.model.layoutDidChange(Fixtures.fourDisplays)
        h.scheduler.advance(by: 1)
        await h.model.cameraOperation?.value

        #expect(!h.model.isCameraActive, "Two seconds after the first change")
    }

    @Test func turningTrackingOffDuringTheGraceStopsTheCameraAtOnce() async {
        let h = await graceHarness()
        defer { h.tearDown() }
        h.model.layoutDidChange(Fixtures.oneDisplay)
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive)

        await h.model.setTrackingEnabled(false)

        #expect(!h.model.isCameraActive)
        #expect(!h.scheduler.hasPending)
    }

    @Test func quittingDuringTheGraceStopsTheCameraAtOnce() async {
        let h = await graceHarness()
        defer { h.tearDown() }
        h.model.layoutDidChange(Fixtures.oneDisplay)
        await h.model.cameraOperation?.value

        await h.model.shutdown()

        #expect(!h.model.isCameraActive)
        #expect(h.camera.stopCount >= 1)
        #expect(!h.scheduler.hasPending)
    }

    @Test func aCalibrationRemovedByTheUserStopsTheCameraAtOnce() async throws {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        let key = try #require(h.model.activeCalibration?.saved.key)

        h.model.removeFromLibrary(key)
        await h.model.cameraOperation?.value

        #expect(!h.model.isCameraActive, "Only a display change gets the grace")
        #expect(!h.scheduler.scheduledDelays.contains(AppModel.cameraGraceDelay))
    }

    @Test func choosingACameraWithoutACalibrationStopsTheCameraAtOnce() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        await h.model.selectCamera(external.id)
        await h.model.cameraOperation?.value

        #expect(!h.model.isCameraActive)
        #expect(!h.scheduler.scheduledDelays.contains(AppModel.cameraGraceDelay))
    }

    @Test func aDisplayChangeWhileNothingRunsSchedulesNothing() {
        let h = Harness.make(layout: Fixtures.threeDisplays, calibrated: true)
        defer { h.tearDown() }

        h.model.layoutDidChange(Fixtures.oneDisplay)

        #expect(!h.scheduler.hasPending)
    }

    // MARK: Item 7: the USB camera fallback

    /// Tracking on with the saved choice (the external camera) running, and a calibration for each of `cameras`.
    private func fallbackHarness(
        cameras: [CameraDevice] = [Fixtures.builtInCamera, Fixtures.externalCamera],
        calibrated: [CameraDevice] = [Fixtures.builtInCamera, Fixtures.externalCamera]
    ) async -> Harness {
        let h = Harness.make(
            autoRun: true, savedCameraID: Fixtures.externalCamera.id, calibrated: true,
            calibrationCameras: calibrated.map(\.name))
        h.camera.setDevices(cameras)
        h.model.refreshEnvironment()
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status == .running(Fixtures.externalCamera) }
        await h.model.cameraOperation?.value
        return h
    }

    /// The chosen camera is unplugged: capture is interrupted, and the model learns of it half a second later.
    private func unplugExternal(_ h: Harness, leaving remaining: [CameraDevice]? = nil) {
        h.camera.setDevices(remaining ?? [builtIn])
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
    }

    private func replugExternal(_ h: Harness, cameras: [CameraDevice]? = nil) {
        h.camera.setDevices(cameras ?? [builtIn, external])
        h.notifications.post(name: connected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
    }

    @Test func theChosenCameraUnpluggedForFiveSecondsFallsBackToACalibratedCamera() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }

        unplugExternal(h)
        #expect(h.model.trackingStatus == .cameraDisconnected(external.name))
        #expect(h.model.statusLine == "Logitech C922 disconnected")
        #expect(h.model.activeCalibration?.saved.cameraName == external.name, "Waiting keeps its own calibration")
        #expect(h.model.isCameraActive)
        #expect(AppModel.cameraFallbackDelay == 5)

        h.scheduler.advance(by: 4.99)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1, "Not yet")

        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value
        #expect(h.pose.configurations.map(\.cameraDeviceID) == ["cam-external", "cam-builtin"])
        #expect(h.model.fallbackCamera == builtIn)
        let running = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        #expect(running)
        #expect(h.model.activeCalibration?.saved.cameraName == builtIn.name)
        #expect(h.model.trackingStatus == .noFace)
    }

    @Test func aFallbackNeverChangesTheSavedChoice() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }

        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        #expect(h.model.fallbackCamera != nil)
        #expect(h.model.selectedCameraID == external.id)
        #expect(h.defaults.string(forKey: "sway.cameraDeviceID") == external.id)
        #expect(h.relaunchedModel().selectedCameraID == external.id)
    }

    @Test func theChosenCameraComingBackRestartsOnIt() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }

        replugExternal(h)
        await h.model.cameraOperation?.value

        #expect(h.model.fallbackCamera == nil)
        #expect(h.pose.configurations.map(\.cameraDeviceID) == ["cam-external", "cam-builtin", "cam-external"])
        let back = await waitUntil { h.model.status == .running(Fixtures.externalCamera) }
        #expect(back)
        #expect(h.model.activeCalibration?.saved.cameraName == external.name)
        #expect(h.model.selectedCameraID == external.id)
    }

    @Test func theChosenCameraComingBackBeforeTheFallbackJustKeepsGoing() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 3)

        // The camera service restarts the same device by itself when it returns.
        replugExternal(h)
        h.model.handle(.status(.starting))
        h.model.handle(.status(.running(external)))
        h.scheduler.advance(by: 10)
        await h.model.cameraOperation?.value

        #expect(h.pose.startCount == 1, "Gander never restarted anything")
        #expect(h.model.fallbackCamera == nil)
        #expect(h.model.trackingStatus == .noFace)
    }

    @Test func aCalibratedCameraTakesOverWhileTheWaitBeforeItShowsTheMissingCamera() async {
        let h = await fallbackHarness(calibrated: [external, builtIn])
        defer { h.tearDown() }

        unplugExternal(h)
        h.scheduler.advance(by: 4.99)
        await h.model.cameraOperation?.value
        #expect(h.model.statusLine == "Logitech C922 disconnected", "Waiting for the five seconds")
        #expect(h.model.trackingEnabled)
        #expect(h.pose.stopCount == 0)

        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled, "A calibrated camera exists: nothing turns off")
        #expect(h.pose.configurations.map(\.cameraDeviceID) == ["cam-external", "cam-builtin"])
    }

    @Test func theBuiltInCameraIsPreferredAndOtherwiseTheFirstCalibratedOne() async {
        let h = await fallbackHarness(
            cameras: [otherUSB, builtIn, external], calibrated: [builtIn, external, otherUSB])
        defer { h.tearDown() }

        h.camera.setDevices([otherUSB, builtIn])
        h.model.refreshEnvironment()
        #expect(h.model.fallbackCandidate() == builtIn)

        h.model.removeFromLibrary(Fixtures.profile(cameraName: builtIn.name).key)
        #expect(h.model.fallbackCandidate() == otherUSB)
    }

    @Test func aStandInThatIsNotTheBuiltInCameraKeepsTrackingRunningAfterTheRestart() async {
        // The restart passes through a moment with no stream, where the calibration must still be the stand-in's.
        let h = await fallbackHarness(
            cameras: [otherUSB, builtIn, external], calibrated: [external, otherUSB])
        defer { h.tearDown() }

        unplugExternal(h, leaving: [otherUSB, builtIn])
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        #expect(h.model.fallbackCamera == otherUSB, "The built-in camera has no calibration")
        #expect(h.pose.configurations.map(\.cameraDeviceID) == ["cam-external", "cam-other"])
        let running = await waitUntil { h.model.status == .running(Fixtures.secondExternalCamera) }
        #expect(running)
        #expect(h.model.isCameraActive)
        #expect(h.model.activeCalibration?.saved.cameraName == otherUSB.name)
    }

    @Test func aCameraThatIsNotConnectedIsNeverAFallback() async {
        let h = await fallbackHarness(calibrated: [builtIn, external])
        defer { h.tearDown() }

        unplugExternal(h, leaving: [otherUSB])
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.model.fallbackCamera == nil, "The built-in camera has a calibration but is not connected")
        #expect(h.pose.startCount == 1)
        #expect(!h.model.trackingEnabled, "Nothing usable is left, so Tracking is off")
    }

    @Test func aCameraStillConnectedButBusyNeverFallsBack() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }

        h.model.handle(.status(.interrupted("Camera is in use by another app")))
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.model.statusLine == "Camera busy")
        #expect(h.pose.startCount == 1)
        #expect(h.model.fallbackCamera == nil)
    }

    @Test func aRecoveryBeforeTheFiveSecondsStartsTheWaitAgain() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 3)

        h.model.handle(.status(.running(external)))
        #expect(!h.scheduler.hasPending, "Frames came back: the wait is over")
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.scheduler.advance(by: 3)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1, "Three seconds into the new wait")

        h.scheduler.advance(by: 2)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 2)
    }

    @Test func aDefaultChoiceNeverFallsBack() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.camera.setDevices([external])
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.pose.startCount == 1)
        #expect(h.model.fallbackCamera == nil)
    }

    @Test func aCameraCaptureOpenedOnItsOwnIsNotTheChosenOne() async {
        // The chosen camera was never connected in this run: capture opened the built-in one instead.
        let h = Harness.make(
            savedCameraID: external.id, calibrated: true, calibrationCameras: [builtIn.name, external.name])
        defer { h.tearDown() }
        h.camera.setDevices([builtIn])
        h.model.refreshEnvironment()
        await h.model.setTrackingEnabled(true)
        h.reportRunning()

        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.model.unpluggedChosenCamera == nil)
        #expect(h.model.statusLine == "Interrupted: Camera disconnected")
        #expect(h.pose.startCount == 1)
    }

    @Test func neverSwitchesCamerasWhileTheSetupWindowRuns() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        let starts = h.pose.startCount

        unplugExternal(h)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == starts)
        #expect(h.model.fallbackCamera == nil)

        h.model.closeSetup()
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera == builtIn, "Setup is closed: the wait that already ran out ends")
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-builtin")
    }

    @Test func neverSwitchesCamerasWhileTheGateTestRuns() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        // A run waiting for its camera: an interruption does not abort it (a running run would abort).
        h.model.gateRunState = .startingCamera
        let starts = h.pose.startCount

        unplugExternal(h)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == starts)
        #expect(h.model.fallbackCamera == nil)

        h.model.gateRunState = .idle
        h.model.syncTrackingActivity()
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera == builtIn, "The run is over: the wait that already ran out ends")
    }

    @Test func theChosenCameraComingBackWaitsForSetupToClose() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera == builtIn)
        h.openSetup()
        await h.model.cameraOperation?.value
        let starts = h.pose.startCount

        replugExternal(h)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == starts, "Setup is open: the camera stays as it is")
        #expect(h.model.fallbackCamera == builtIn)

        h.model.closeSetup()
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera == nil)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
    }

    @Test func theChosenCameraComingBackWhileSuspendedWaitsForTheWake() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        h.model.handle(.status(.suspended(.screenLocked)))
        let starts = h.pose.startCount

        h.camera.setDevices([builtIn, external])
        h.model.refreshEnvironment()
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == starts, "Nothing restarts while the camera is suspended")
        #expect(h.model.fallbackCamera == builtIn)

        h.model.handle(.status(.running(builtIn)))
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera == nil)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
    }

    // MARK: No usable fallback turns Tracking off (SPEC D46, revised)

    /// The external camera is unplugged and only it is calibrated; five seconds have passed.
    private func lostCameraHarness() async -> Harness {
        let h = await fallbackHarness(calibrated: [external])
        unplugExternal(h)
        h.scheduler.advance(by: AppModel.cameraFallbackDelay)
        await h.model.cameraOperation?.value
        return h
    }

    @Test func withNoCalibratedCameraTheFiveSecondsTurnTrackingOffAndStopTheCamera() async {
        let h = await fallbackHarness(calibrated: [external])
        defer { h.tearDown() }
        unplugExternal(h)

        h.scheduler.advance(by: 4.99)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled, "Not yet")
        #expect(h.model.isCameraActive)
        #expect(h.model.statusLine == "Logitech C922 disconnected")

        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value
        #expect(!h.model.trackingEnabled)
        #expect(!h.model.isCameraActive, "The camera light goes off")
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.status == .stopped)
        #expect(!h.scheduler.hasPending, "No timer is left behind")
        #expect(h.model.fallbackCamera == nil)
        #expect(h.pose.startCount == 1)
    }

    @Test func turningTrackingOffForALostCameraNeverWritesTheSavedChoice() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }

        #expect(!h.model.trackingEnabled)
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"), "The saved choice is the user's, still on (D23)")
        #expect(h.relaunchedModel().trackingEnabled)
        #expect(h.model.selectedCameraID == external.id)
        #expect(h.defaults.string(forKey: "sway.cameraDeviceID") == external.id)
    }

    @Test func whileTheCameraIsGoneTheStatusNamesItInsteadOfPaused() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }

        #expect(h.model.trackingStatus == .cameraDisconnected(external.name))
        #expect(h.model.statusLine == "Logitech C922 disconnected")
        #expect(h.model.menuBarGlyph == .attention, "The same \"needs you\" glyph as before")
    }

    @Test func whenTheCameraComesBackTheStatusIsPausedAndTrackingStaysOff() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }
        let starts = h.pose.startCount

        replugExternal(h)
        await h.model.cameraOperation?.value
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingStatus == .paused)
        #expect(h.model.statusLine == "Paused")
        #expect(!h.model.trackingEnabled, "Tracking does not come back by itself")
        #expect(h.pose.startCount == starts)
        #expect(!h.model.isCameraActive)
        #expect(h.model.menuBarGlyph == .paused)
    }

    @Test func theUserCanTurnTrackingOnAfterTheCameraReturnsAndItRunsOnTheChosenCamera() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }
        replugExternal(h)

        await h.model.setTrackingEnabled(true)

        #expect(h.model.trackingEnabled)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
        let running = await waitUntil { h.model.status == .running(Fixtures.externalCamera) }
        #expect(running)
        #expect(h.model.activeCalibration?.saved.cameraName == external.name)
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"))
    }

    @Test func turningTrackingOnWhileTheCameraIsStillGoneAddsNoLoop() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }
        let starts = h.pose.startCount

        // Nothing is calibrated for the camera capture would open now: Tracking waits for a calibration, as before.
        await h.model.setTrackingEnabled(true)
        await h.model.cameraOperation?.value
        h.scheduler.advance(by: 60)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .needsCalibration)
        #expect(h.pose.startCount == starts)
        #expect(!h.scheduler.hasPending)
    }

    @Test func turningTrackingOnWhileTheCameraIsStillGoneAndNotReadyUsesTheExistingFailurePath() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }
        // The built-in camera gets a calibration, so capture's own rule has something to start; the camera is not ready.
        h.model.saveToLibrary(Fixtures.profile(cameraName: builtIn.name))
        h.pose.failNextStarts(with: [.noDevice])

        await h.model.setTrackingEnabled(true)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled, "Turned off again, as for any camera that cannot start")
        #expect(h.model.trackingStatus == .cameraFailed)
        h.scheduler.advance(by: 60)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 2, "One try, no loop")
        #expect(!h.scheduler.hasPending)
    }

    @Test func pickingAnotherCameraEndsTheLostCameraStatus() async {
        let h = await lostCameraHarness()
        defer { h.tearDown() }

        await h.model.selectCamera(builtIn.id)

        #expect(h.model.trackingStatus != .cameraDisconnected(external.name))
        #expect(h.model.lostCameraID == nil)
    }

    @Test func aStandInThatIsAlsoDisconnectedWithNothingElseUsableTurnsTrackingOff() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        #expect(h.model.fallbackCamera == builtIn)

        h.camera.setDevices([])
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
        h.scheduler.advance(by: 4.99)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled, "Not yet")

        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(!h.model.isCameraActive)
        #expect(h.model.fallbackCamera == nil)
        #expect(h.model.trackingStatus == .cameraDisconnected(external.name), "The camera the user chose")
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"))
        #expect(!h.scheduler.hasPending)
    }

    @Test func aStandInThatIsAlsoDisconnectedMovesToAnotherCalibratedCameraIfThereIsOne() async {
        let h = await fallbackHarness(
            cameras: [builtIn, external, otherUSB], calibrated: [external, builtIn, otherUSB])
        defer { h.tearDown() }
        unplugExternal(h, leaving: [builtIn, otherUSB])
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        #expect(h.model.fallbackCamera == builtIn)

        h.camera.setDevices([otherUSB])
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.model.fallbackCamera == otherUSB)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-other")
    }

    @Test func aFailedRetryWithNothingLeftToUseTurnsTrackingOffAndClearsTheRetry() async {
        let h = await fallbackHarness(calibrated: [external, builtIn])
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.noDevice])
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled, "The first failure only waits for the next try")
        #expect(h.scheduler.hasPending, "A retry is waiting")

        h.camera.setDevices([])
        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraDisconnected(external.name))
        #expect(!h.scheduler.hasPending, "The retry is cancelled with it")
    }

    @Test func nothingTurnsOffWhileTheSetupWindowRunsAndItDoesAfterItCloses() async {
        let h = await fallbackHarness(calibrated: [external])
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value

        unplugExternal(h)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled)
        #expect(h.model.isCameraActive)

        h.model.closeSetup()
        await h.model.cameraOperation?.value
        #expect(!h.model.trackingEnabled, "The wait had already run out")
        #expect(!h.model.isCameraActive)
    }

    @Test func nothingTurnsOffWhileTheGateTestRuns() async {
        let h = await fallbackHarness(calibrated: [external])
        defer { h.tearDown() }
        h.model.gateRunState = .startingCamera

        unplugExternal(h)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.model.isCameraActive)
        #expect(h.model.lostCameraID == nil)

        h.model.gateRunState = .idle
        h.model.syncTrackingActivity()
        await h.model.cameraOperation?.value
        #expect(!h.model.trackingEnabled, "The run is over")
    }

    @Test func nothingTurnsOffWhileTheCameraIsSuspended() async {
        let h = await fallbackHarness(calibrated: [external])
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 3)

        h.model.handle(.status(.suspended(.screenLocked)))
        h.scheduler.advance(by: 60)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled)
        #expect(h.model.isCameraActive)
        #expect(h.pose.stopCount == 0)

        // After the wake the camera is still missing: the five seconds start again.
        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.scheduler.advance(by: 4.99)
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled)
        h.scheduler.advance(by: 0.01)
        await h.model.cameraOperation?.value
        #expect(!h.model.trackingEnabled)
    }

    @Test func aChosenCameraThatIsStillConnectedNeverTurnsTrackingOff() async {
        let h = await fallbackHarness(calibrated: [external])
        defer { h.tearDown() }

        h.model.handle(.status(.interrupted("Camera is in use by another app")))
        h.scheduler.advance(by: 60)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.model.statusLine == "Camera busy")
    }

    // MARK: A failed restart during a fallback never turns Tracking off

    /// A fallback that is running on the built-in camera while the external one stays unplugged.
    private func standInHarness() async -> Harness {
        let h = await fallbackHarness()
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        return h
    }

    @Test func aFailedSwitchBackKeepsTrackingOnAndPutsTheStandInBack() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.deviceUnavailable("Camera is not ready")])

        replugExternal(h)
        _ = await waitUntil { h.pose.startCount == 4 }
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled, "A camera just plugged in may not be ready to open")
        #expect(
            h.pose.configurations.map(\.cameraDeviceID) == [
                "cam-external", "cam-builtin", "cam-external", "cam-builtin",
            ])
        #expect(h.model.fallbackCamera == builtIn)
        let running = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        #expect(running)
        #expect(h.model.trackingStatus != .cameraFailed)
        #expect(h.model.selectedCameraID == external.id)
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"), "The saved choice is the user's, and still on")
    }

    @Test func aFailedSwitchBackIsNotRetriedInALoopAndTriesAgainLater() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.noDevice])
        replugExternal(h)
        _ = await waitUntil { h.pose.startCount == 4 }
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }

        // The stand-in's own status changes must not trigger another switch back at once.
        h.model.syncTrackingActivity()
        h.model.refreshActiveCalibration()
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 4)

        h.scheduler.advance(by: AppModel.cameraFallbackDelay)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 5)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
        #expect(h.model.fallbackCamera == nil)
        let back = await waitUntil { h.model.status == .running(Fixtures.externalCamera) }
        #expect(back)
        #expect(h.model.trackingEnabled)
    }

    @Test func aDeviceChangeTriesAFailedSwitchBackAgain() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.deviceUnavailable("Camera is not ready")])
        replugExternal(h)
        _ = await waitUntil { h.pose.startCount == 4 }
        await h.model.cameraOperation?.value

        h.camera.setDevices([builtIn, external, otherUSB])
        h.notifications.post(name: connected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
        await h.model.cameraOperation?.value

        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
        #expect(h.model.fallbackCamera == nil)
    }

    @Test func aFailedStandInStartKeepsTrackingOnAndTheNextDeviceChangeTriesAgain() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.noDevice])

        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"))
        #expect(!h.model.isCameraActive)
        #expect(h.model.fallbackCamera == nil)
        #expect(h.pose.startCount == 2)

        h.notifications.post(name: disconnected, object: nil)
        h.scheduler.advance(by: AppModel.environmentRefreshDelay)
        await h.model.cameraOperation?.value

        #expect(h.pose.configurations.map(\.cameraDeviceID) == ["cam-external", "cam-builtin", "cam-builtin"])
        #expect(h.model.fallbackCamera == builtIn)
        let running = await waitUntil { h.model.status == .running(Fixtures.builtInCamera) }
        #expect(running)
        #expect(h.model.trackingEnabled)
    }

    @Test func aFailedStandInStartIsAlsoRetriedByTheTimer() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.deviceUnavailable("Camera is not ready")])
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)

        h.scheduler.advance(by: AppModel.cameraFallbackDelay)
        await h.model.cameraOperation?.value

        #expect(h.model.fallbackCamera == builtIn)
        #expect(h.model.isCameraActive)
        #expect(h.model.trackingEnabled)
    }

    @Test func aSwitchBackThatFailsAfterTheStandInAlsoFailedStartsTheChosenCameraWhenItIsReady() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        // The switch back fails, and so does the stand-in's restart: nothing runs, Tracking is still on.
        h.pose.failNextStarts(with: [.deviceUnavailable("Camera is not ready"), .deviceUnavailable("Still busy")])
        replugExternal(h)
        _ = await waitUntil { h.pose.startCount == 4 }
        await h.model.cameraOperation?.value
        #expect(h.model.trackingEnabled)
        #expect(!h.model.isCameraActive)

        h.scheduler.advance(by: AppModel.cameraFallbackDelay)
        await h.model.cameraOperation?.value

        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
        #expect(h.model.isCameraActive)
        #expect(h.model.trackingEnabled)
    }

    @Test func anotherErrorOnTheStandInStartStillTurnsTrackingOff() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.configurationFailed("No format")])

        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraFailed)
    }

    @Test func anotherErrorOnTheSwitchBackStillTurnsTrackingOff() async {
        let h = await standInHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.runtimeFailure("Sensor died")])

        replugExternal(h)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraFailed)
        #expect(h.model.fallbackCamera == nil)
    }

    @Test func aNotReadyCameraWhoseStartTheUserAskedForStillTurnsTrackingOff() async {
        // Only the restarts the fallback itself begins are forgiven.
        let h = await standInHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.deviceUnavailable("Camera is not ready")])

        await h.model.selectCamera(builtIn.id)
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraFailed)
    }

    @Test func pausingWhileAFailedFallbackWaitsForItsRetryEndsTheWait() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        h.pose.failNextStarts(with: [.noDevice])
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        let starts = h.pose.startCount

        await h.model.setTrackingEnabled(false)
        h.scheduler.advance(by: 30)
        await h.model.cameraOperation?.value

        #expect(h.pose.startCount == starts)
        #expect(!h.model.isCameraActive)
    }

    @Test func choosingACameraEndsTheFallback() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value
        #expect(h.model.fallbackCamera != nil)

        await h.model.selectCamera(builtIn.id)

        #expect(h.model.fallbackCamera == nil)
        #expect(h.model.selectedCameraID == builtIn.id)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-builtin")
    }

    @Test func pausingDuringAFallbackForgetsItAndTheNextStartUsesTheSavedChoice() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        h.scheduler.advance(by: 5)
        await h.model.cameraOperation?.value

        await h.model.setTrackingEnabled(false)
        #expect(h.model.fallbackCamera == nil)
        #expect(!h.model.isCameraActive)

        await h.model.setTrackingEnabled(true)
        #expect(h.pose.configurations.last?.cameraDeviceID == "cam-external")
    }

    @Test func quittingForgetsTheWait() async {
        let h = await fallbackHarness()
        defer { h.tearDown() }
        unplugExternal(h)
        #expect(h.scheduler.hasPending)

        h.model.applicationWillTerminate()

        #expect(!h.scheduler.hasPending)
    }

    // MARK: Item 8: a steadier "No face"

    @Test func noFaceShowsHalfASecondAfterTheLastFaceAndAFaceShowsAtOnce() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        feed(h, at: 1)
        #expect(h.model.trackingStatus == .tracking)

        feed(h, at: 1.2, face: false)
        feed(h, at: 1.49, face: false)
        #expect(h.model.trackingStatus == .tracking)
        #expect(h.model.hasFace)

        feed(h, at: 1.5, face: false)
        #expect(h.model.trackingStatus == .noFace)
        #expect(h.model.statusLine == "No face \u{00B7} FaceTime HD Camera")

        feed(h, at: 1.57)
        #expect(h.model.trackingStatus == .tracking)
    }

    @Test func theDeciderSeesTheRawNoFaceSampleWhileOnlyTheStatusIsSteadied() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        feed(h, at: 1)
        let recorder = h.engine.lastRecorder

        feed(h, at: 1.2, face: false)

        #expect(h.model.hasFace, "The status still shows the face")
        #expect(h.model.trackingStatus == .tracking)
        #expect(recorder?.samples.count == 2)
        #expect(recorder?.samples.last?.pose == nil, "The decider got the sample as it was")
        #expect(h.model.latestSample?.pose == nil)
    }

    @Test func aGlitchOfOneFrameNeverShowsNoFace() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        for index in 0..<60 {
            feed(h, at: Double(index) / 15, face: index % 10 != 5)
            #expect(h.model.trackingStatus == .tracking, "Frame \(index)")
        }
    }

    @Test func aRestartedCameraShowsNoFaceUntilTheFirstFaceAndThenAtOnce() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        feed(h, at: 1)

        h.model.handle(.status(.interrupted("Camera disconnected")))
        h.model.handle(.status(.running(builtIn)))
        feed(h, at: 1.1, face: false)
        #expect(!h.model.hasFace, "Nothing to wait for after a restart")

        feed(h, at: 1.2)
        #expect(h.model.hasFace)
    }
}
