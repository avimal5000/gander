import AppKit
import Foundation
import GanderModels
import Testing

@testable import GanderUI

@MainActor
@Suite("AppModel camera and pose")
struct AppModelCameraTests {
    // MARK: Start and stop

    @Test func turningTrackingOnStartsThePoseSourceAndOffStopsIt() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.model.trackingEnabled)
        #expect(h.pose.startCount == 1)
        let running = await waitUntil { h.model.status.isRunning }
        #expect(running)
        #expect(h.model.statusLine == "No face \u{00B7} FaceTime HD Camera")
        #expect(h.model.menuBarSymbol == "eye.trianglebadge.exclamationmark")

        await h.model.setTrackingEnabled(false)
        #expect(!h.model.trackingEnabled)
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.status == .stopped)
        #expect(h.model.latestSample == nil)
        #expect(h.model.menuBarSymbol == "eye.slash")
        #expect(!h.model.isCameraActive)
    }

    @Test func theConfigurationCarriesTheSelectedCameraAndDefaultFrameRate() async {
        let h = Harness.make(
            autoRun: true, savedCameraID: Fixtures.externalCamera.id, calibrated: true,
            calibrationCameras: [Fixtures.externalCamera.name])
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.pose.configurations == [PoseSourceConfiguration(cameraDeviceID: "cam-external")])
        #expect(h.pose.configurations.first?.frameRate == GanderPolicy.defaultFrameRate)
    }

    @Test func nothingStartsUntilSomethingAsksForTheCamera() {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        #expect(h.pose.startCount == 0)
        #expect(h.model.status == .stopped)
        #expect(!h.model.trackingEnabled)
    }

    @Test func queuedCameraWorkEvaluatesTheLatestRequestWhenItRuns() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        h.model.trackingEnabled = true
        let first = h.model.reconcileCamera()
        h.model.trackingEnabled = false
        let second = h.model.reconcileCamera()
        h.model.trackingEnabled = true
        let third = h.model.reconcileCamera()
        await first.value
        await second.value
        await third.value

        #expect(h.pose.startCount == 1)
        #expect(h.model.isCameraActive)
        #expect(h.pose.isStreaming)
    }

    // MARK: Events

    @Test func samplesUpdateTheLatestPoseHistoryAndFrameRate() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        await h.startTracking()
        for index in 0..<60 {
            h.model.handle(.sample(Fixtures.sample(at: Double(index) / 15, yaw: Double(index))))
        }
        #expect(h.model.latestSample?.pose?.yaw == 59)
        #expect(h.model.hasFace)
        #expect(abs(h.model.fps - 15) < 0.001)
        #expect(h.model.menuBarSymbol == "eye.fill")
        #expect(!h.model.history.points.isEmpty)

        // "No face" shows only after half a second without one (CONTRACT 6.5.5 item 8); the last face was at 3.93 s.
        h.model.handle(.sample(Fixtures.sample(at: 4.1, face: false)))
        #expect(h.model.hasFace)
        #expect(h.model.menuBarSymbol == "eye.fill")
        h.model.handle(.sample(Fixtures.sample(at: 4.5, face: false)))
        #expect(!h.model.hasFace)
        #expect(h.model.menuBarSymbol == "eye.trianglebadge.exclamationmark")
    }

    @Test func textReadoutsRefreshFiveTimesASecondAndAFaceChangeAtOnce() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.reportRunning()
        h.model.handle(.sample(Fixtures.sample(at: 10, yaw: 1)))
        #expect(h.model.readout.pose?.yaw == 1)

        h.model.handle(.sample(Fixtures.sample(at: 10.1, yaw: 2)))
        #expect(h.model.readout.pose?.yaw == 1)
        // Everything else still follows every frame.
        #expect(h.model.latestSample?.pose?.yaw == 2)

        h.model.handle(.sample(Fixtures.sample(at: 10.25, yaw: 3)))
        #expect(h.model.readout.pose?.yaw == 3)
        #expect(h.model.readout.fps > 0)

        h.model.handle(.sample(Fixtures.sample(at: 10.3, face: false)))
        #expect(h.model.readout.pose == nil)
    }

    @Test func eventsFlowFromTheStreamIntoTheModel() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.pose.emit(.sample(Fixtures.sample(at: 1, yaw: 12)))
        let arrived = await waitUntil { h.model.latestSample?.pose?.yaw == 12 }
        #expect(arrived)
    }

    @Test func leavingTheRunningStateClearsTheLiveNumbers() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        await h.startTracking()
        h.run(frames: 5, dt: 0.1)
        #expect(h.model.latestSample != nil)

        h.model.handle(.status(.suspended(.screenLocked)))
        #expect(h.model.latestSample == nil)
        #expect(h.model.fps == 0)
        #expect(h.model.readout == LiveReadout())
        #expect(h.model.statusLine == "Suspended: screen locked")
        #expect(h.model.menuBarSymbol == "pause.circle")

        h.model.handle(.status(.interrupted("Camera disconnected")))
        #expect(h.model.menuBarSymbol == "exclamationmark.triangle")
    }

    @Test func aFailedStatusSwitchesTrackingOffInMemoryAndKeepsTheSavedChoice() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.pose.emit(.status(.failed(.runtimeFailure("sensor died"))))
        _ = await waitUntil { !h.model.trackingEnabled }
        await h.model.cameraOperation?.value

        #expect(!h.model.trackingEnabled)
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.status == .failed(.runtimeFailure("sensor died")))
        #expect(h.model.statusLine == "Camera unavailable")
        #expect(h.model.menuBarSymbol == "exclamationmark.triangle")
        // The user's choice is untouched: the next launch tries again.
        #expect(h.defaults.bool(forKey: "gander.trackingEnabled"))
    }

    @Test func theRealCamerasRecoverableStatusesKeepTrackingOn() async {
        // What CameraCaptureService reports through LivePoseSource for sleep, a stall and an unplug, each followed
        // by recovery. None of these may switch Tracking off or restart the source; only `.failed` does.
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let camera = Fixtures.builtInCamera

        await h.model.setTrackingEnabled(true)
        for status: CaptureStatus in [
            .starting, .running(camera), .running(camera),
            .suspended(.systemSleep), .starting, .running(camera),
            .interrupted("No frames from the camera"), .running(camera),
            .interrupted("Camera disconnected"), .starting, .running(camera),
        ] {
            h.pose.emit(.status(status))
        }
        let settled = await waitUntil { h.model.status == .running(camera) }
        await h.model.cameraOperation?.value

        #expect(settled)
        #expect(h.model.trackingEnabled)
        #expect(h.model.isCameraActive)
        #expect(h.pose.startCount == 1)
        #expect(h.pose.stopCount == 0)
    }

    @Test func aLateStoppedFromTheStoppedStreamDoesNotHideTheFailure() async {
        // After a cancel, AsyncStream can still deliver what the source yielded from `stop()`. That `.stopped` must
        // not replace the failure on screen.
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        let generation = h.model.streamGeneration
        h.model.handleStreamEvent(.status(.failed(.runtimeFailure("sensor died"))), generation: generation)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)

        h.model.handleStreamEvent(.status(.stopped), generation: generation)
        h.model.handleStreamEvent(.sample(Fixtures.sample(at: 1)), generation: generation)

        #expect(h.model.status == .failed(.runtimeFailure("sensor died")))
        #expect(h.model.latestSample == nil)
    }

    @Test func eventsFromTheStreamOfAnEarlierRunAreIgnoredAfterARestart() async {
        let h = Harness.make(
            autoRun: true, calibrated: true,
            calibrationCameras: [Fixtures.builtInCamera.name, Fixtures.externalCamera.name])
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        let first = h.model.streamGeneration
        await h.model.selectCamera("cam-external")
        _ = await waitUntil { h.model.status.isRunning }
        let second = h.model.streamGeneration
        #expect(second != first)

        h.model.handleStreamEvent(.status(.stopped), generation: first)
        #expect(h.model.status.isRunning)
        #expect(h.model.trackingEnabled)

        h.model.handleStreamEvent(.status(.interrupted("Camera disconnected")), generation: second)
        #expect(h.model.status == .interrupted("Camera disconnected"))
    }

    @Test func aStreamThatEndsOnItsOwnTurnsTrackingOffInMemory() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.pose.finishStream()
        let off = await waitUntil { !h.model.trackingEnabled }
        #expect(off)
        #expect(!h.model.isCameraActive)
        #expect(h.model.status == .stopped)
        #expect(h.defaults.bool(forKey: "gander.trackingEnabled"))
    }

    // MARK: Camera selection

    @Test func theSelectedCameraIsPersistedAndRestored() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(h.model.selectedCameraID == nil)

        await h.model.selectCamera("cam-external")
        #expect(h.defaults.string(forKey: "gander.cameraDeviceID") == "cam-external")
        #expect(h.relaunchedModel().selectedCameraID == "cam-external")

        await h.model.selectCamera(nil)
        #expect(h.defaults.object(forKey: "gander.cameraDeviceID") == nil)
        #expect(h.relaunchedModel().selectedCameraID == nil)
    }

    @Test func changingTheCameraWhileRunningRestartsOnTheNewDevice() async {
        let h = Harness.make(
            autoRun: true, calibrated: true,
            calibrationCameras: [Fixtures.builtInCamera.name, Fixtures.externalCamera.name])
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        await h.model.selectCamera("cam-external")

        #expect(h.pose.configurations.map(\.cameraDeviceID) == [nil, "cam-external"])
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.isCameraActive)
        let again = await waitUntil { h.model.status.isRunning }
        #expect(again)
    }

    @Test func changingTheCameraWhileOffDoesNotStartIt() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.selectCamera("cam-external")
        #expect(h.pose.startCount == 0)
    }

    @Test func refreshingReadsDevicesAndPermission() {
        let h = Harness.make(authorization: .notDetermined, calibrated: true)
        defer { h.tearDown() }
        #expect(h.model.devices.map(\.id) == ["cam-builtin", "cam-external"])

        h.camera.setDevices([Fixtures.builtInCamera])
        h.camera.setAuthorization(.authorized)
        h.model.refreshEnvironment()
        #expect(h.model.devices.map(\.id) == ["cam-builtin"])
        #expect(h.model.authorization == .authorized)
    }

    // MARK: Permission

    @Test func aFirstRunShowsTheExplanationInsteadOfStarting() async {
        let h = Harness.make(authorization: .notDetermined, autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.model.permissionPrompt == .explanation)
        #expect(h.pose.startCount == 0)
        #expect(h.camera.requestCount == 0)
        #expect(!h.model.trackingEnabled)
        #expect(h.model.pendingIntent == .tracking)
    }

    @Test func continuingAfterTheExplanationAsksTheSystemThenStarts() async {
        let h = Harness.make(authorization: .notDetermined, autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        await h.model.continueAfterPermissionExplanation()

        #expect(h.camera.requestCount == 1)
        #expect(h.model.authorization == .authorized)
        #expect(h.model.permissionPrompt == nil)
        #expect(h.model.trackingEnabled)
        #expect(h.pose.startCount == 1)
    }

    @Test func decliningTheSystemPromptShowsHowToEnableAccess() async {
        let h = Harness.make(authorization: .notDetermined, autoRun: true, calibrated: true)
        defer { h.tearDown() }
        h.camera.setAuthorizationAfterRequest(.denied)

        await h.model.setTrackingEnabled(true)
        await h.model.continueAfterPermissionExplanation()

        #expect(h.model.permissionPrompt == .denied)
        #expect(h.pose.startCount == 0)
        // Tracking stays on, blocked: the status asks for camera access, and access granted later resumes it.
        #expect(h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraBlocked)
        #expect(h.model.statusLine == "Camera access needed")
    }

    @Test func notNowDropsTheRequest() async {
        let h = Harness.make(authorization: .notDetermined, autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.defaults.bool(forKey: "gander.trackingEnabled"), "The user flipped the switch")
        h.model.dismissPermissionPrompt()
        #expect(h.model.permissionPrompt == nil)
        #expect(h.model.pendingIntent == nil)
        #expect(!h.defaults.bool(forKey: "gander.trackingEnabled"), "Declining is the user's choice too")
        await h.model.continueAfterPermissionExplanation()
        #expect(h.camera.requestCount == 0)
    }

    @Test func deniedAccessShowsInstructionsAndTheSettingsButtonOpensThePrivacyPane() async {
        let h = Harness.make(authorization: .denied, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.model.permissionPrompt == .denied)
        #expect(h.pose.startCount == 0)
        #expect(h.model.trackingEnabled)

        h.model.openCameraPrivacySettings()
        #expect(h.system.openedSettingsCount == 1)
        #expect(
            AppKitSystemInteractions.cameraPrivacyURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    @Test func restrictedAccessCannotBeFixedHere() async {
        let h = Harness.make(authorization: .restricted, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.model.permissionPrompt == .restricted)
        #expect(h.pose.startCount == 0)
    }

    @Test func aNotAuthorizedErrorWithAStaleAuthorizedStatusStillShowsInstructions() async {
        let h = Harness.make(authorization: .authorized, calibrated: true)
        defer { h.tearDown() }
        h.pose.setStartError(.notAuthorized)

        await h.model.setTrackingEnabled(true)
        #expect(h.pose.startCount == 1)
        #expect(h.model.permissionPrompt == .denied)
        #expect(h.model.trackingEnabled)
    }

    @Test func otherStartupErrorsBecomeAFailedStatus() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.pose.setStartError(.noDevice)

        await h.model.setTrackingEnabled(true)
        #expect(h.model.status == .failed(.noDevice))
        #expect(!h.model.trackingEnabled)
        #expect(h.model.permissionPrompt == nil)
        #expect(h.model.menuBarSymbol == "exclamationmark.triangle")
    }

    @Test func grantingAccessInSystemSettingsClearsTheInstructions() async {
        let h = Harness.make(authorization: .denied, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.model.permissionPrompt == .denied)
        #expect(h.pose.startCount == 0)
        h.camera.setAuthorization(.authorized)
        h.model.refreshEnvironment()
        #expect(h.model.permissionPrompt == nil)
        // The switch was left on, blocked: granting access starts the camera without another click.
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1)
    }

    // MARK: Application lifecycle

    @Test func terminationStopsTheCamera() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.notifications.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(!h.model.trackingEnabled)
        #expect(h.defaults.bool(forKey: "gander.trackingEnabled"), "Quitting is not the user's choice")
        let stopped = await waitUntil { h.pose.stopCount >= 1 && h.camera.stopCount >= 1 }
        #expect(stopped)
    }

    @Test func quitSwitchesTheCameraOffBeforeTerminating() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        await h.model.quit()

        #expect(h.pose.stopCount >= 1)
        #expect(h.camera.stopCount >= 1)
        #expect(h.system.terminateCount == 1)
        #expect(!h.model.isCameraActive)
    }

    // MARK: Windows

    @Test func aWindowRequestLastsUntilTheWindowCloses() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        #expect(!h.model.hasWindowRequest(GanderWindowID.poseDebug))
        h.model.noteWindowRequested(GanderWindowID.poseDebug)
        // Asking repeatedly (the guard's onAppear and viewDidMoveToWindow both check, in either order) never
        // uses the request up.
        #expect(h.model.hasWindowRequest(GanderWindowID.poseDebug))
        #expect(h.model.hasWindowRequest(GanderWindowID.poseDebug))
        #expect(!h.model.hasWindowRequest(GanderWindowID.gateTest))
        // Closing the window clears it, once.
        #expect(h.model.consumeWindowRequest(GanderWindowID.poseDebug))
        #expect(!h.model.hasWindowRequest(GanderWindowID.poseDebug))
        #expect(!h.model.consumeWindowRequest(GanderWindowID.poseDebug))
        // Reopening from the menu after a close works the same way again.
        h.model.noteWindowRequested(GanderWindowID.poseDebug)
        #expect(h.model.hasWindowRequest(GanderWindowID.poseDebug))
    }
}
