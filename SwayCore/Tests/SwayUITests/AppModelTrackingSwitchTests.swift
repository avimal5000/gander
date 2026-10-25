import AppKit
import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel Tracking switch, launch state, and sensitivity")
struct AppModelTrackingSwitchTests {
    private let trackingKey = "sway.trackingEnabled"

    // MARK: The saved choice

    @Test func trackingIsOffByDefault() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .paused)
        #expect(h.model.menuBarSymbol == "eye.slash")
        #expect(h.defaults.object(forKey: trackingKey) == nil)
    }

    @Test func theUsersSwitchWritesTheSavedChoice() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.defaults.bool(forKey: trackingKey))
        await h.model.setTrackingEnabled(false)
        #expect(!h.defaults.bool(forKey: trackingKey))
        #expect(h.defaults.object(forKey: trackingKey) != nil)
    }

    @Test func tracksWithoutACalibrationStillSavesTheChoice() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)

        #expect(h.defaults.bool(forKey: trackingKey))
        #expect(h.pose.startCount == 0, "Nothing fits, so the camera stays off")
    }

    // MARK: Launch

    @Test func launchingWithTrackingSavedOnStartsTheCameraWithoutAnyWindow() async {
        let h = Harness.make(autoRun: true, calibrated: true, trackingSaved: true)
        defer { h.tearDown() }

        #expect(h.model.trackingEnabled)
        let started = await waitUntil { h.pose.startCount == 1 }
        #expect(started)
        let running = await waitUntil { h.model.status.isRunning }
        #expect(running)
        #expect(h.pose.configurations == [PoseSourceConfiguration(cameraDeviceID: nil, includeLandmarks: false)])
        #expect(h.model.trackingStatus == .noFace)
    }

    @Test func theCalibrationIsLookedUpForTheCameraCaptureActuallyOpens() async {
        // No camera chosen, and capture opens the external camera (the system default, say with the lid closed), not
        // the built-in one. Only the external camera is calibrated.
        let h = Harness.make(
            calibrated: true, calibrationCameras: [Fixtures.externalCamera.name], capturePicks: Fixtures.externalCamera,
            trackingSaved: true)
        defer { h.tearDown() }

        let running = await waitUntil { h.model.status.isRunning }
        #expect(running, "Starts at launch: the calibration fits the camera capture will open")
        #expect(h.model.status.device == Fixtures.externalCamera)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1)
        #expect(h.pose.stopCount == 0, "No start-stop loop between the guessed and the running camera")

        // A screen lock suspends capture; the calibration still fits, so the session stays and resumes by itself.
        h.pose.emit(.status(.suspended(.screenLocked)))
        let suspended = await waitUntil { !h.model.status.isRunning }
        #expect(suspended)
        await h.model.cameraOperation?.value
        #expect(h.model.activeCalibration != nil)
        #expect(h.pose.stopCount == 0)
        #expect(h.pose.startCount == 1)
    }

    @Test func aCameraConnectingLaterIsNoticed() async {
        let h = Harness.make(calibrated: true, calibrationCameras: [Fixtures.externalCamera.name])
        defer { h.tearDown() }
        h.camera.setDevices([Fixtures.builtInCamera])
        h.model.refreshEnvironment()
        await h.model.selectCamera(Fixtures.externalCamera.id)
        #expect(h.model.activeCalibration == nil, "The chosen camera is not connected yet")

        h.camera.setDevices([Fixtures.builtInCamera, Fixtures.externalCamera])
        h.notifications.post(name: Notification.Name("AVCaptureDeviceWasConnectedNotification"), object: nil)
        #expect(h.model.predictedCameraName == Fixtures.externalCamera.name)
        #expect(h.model.activeCalibration != nil)
    }

    @Test func launchingWithTrackingSavedOnButNothingCalibratedKeepsTheCameraOff() async {
        let h = Harness.make(autoRun: true, trackingSaved: true)
        defer { h.tearDown() }

        await h.model.cameraOperation?.value

        #expect(h.model.trackingEnabled)
        #expect(h.pose.startCount == 0)
        #expect(h.model.trackingStatus == .needsCalibration)
    }

    @Test func launchingWithTrackingOffDoesNothing() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }

        await h.model.cameraOperation?.value

        #expect(h.pose.startCount == 0)
        #expect(h.model.cameraOperation == nil)
    }

    // MARK: Automatic changes and quitting never change the saved choice

    @Test func aCameraFailureAtStartTurnsTrackingOffInMemoryOnly() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.pose.setStartError(.noDevice)

        await h.model.setTrackingEnabled(true)

        #expect(!h.model.trackingEnabled)
        #expect(h.model.trackingStatus == .cameraFailed)
        #expect(h.defaults.bool(forKey: trackingKey), "The user's choice is still on")
        #expect(h.relaunchedModel().trackingEnabled)
    }

    @Test func quittingLeavesTheSavedChoiceSoTheNextLaunchStartsTracking() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        await h.model.quit()

        #expect(!h.model.trackingEnabled, "Off in memory")
        #expect(h.defaults.bool(forKey: trackingKey), "But still the user's choice")
        #expect(h.system.terminateCount == 1)
        let pose = FakePoseSource(autoRunDevice: Fixtures.builtInCamera)
        let relaunched = h.relaunchedModel(pose: pose)
        #expect(relaunched.trackingEnabled)
        let started = await waitUntil { pose.startCount == 1 }
        #expect(started, "The new model starts tracking")
        _ = await waitUntil { relaunched.status.isRunning }
        await relaunched.shutdown()
    }

    @Test func terminationLeavesTheSavedChoiceToo() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.notifications.post(name: NSApplication.willTerminateNotification, object: nil)

        #expect(!h.model.trackingEnabled)
        #expect(h.defaults.bool(forKey: trackingKey))
        _ = await waitUntil { h.camera.stopCount >= 1 }
        #expect(h.relaunchedModel().trackingEnabled)
    }

    @Test func quittingAfterThePauseSwitchKeepsItPaused() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        await h.model.setTrackingEnabled(false)

        await h.model.quit()

        #expect(!h.defaults.bool(forKey: trackingKey))
        #expect(!h.relaunchedModel().trackingEnabled)
    }

    // MARK: Pausing

    @Test func pausingTurnsTheCameraOffAndTheStatusToPaused() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        await h.model.setTrackingEnabled(false)

        #expect(!h.model.isCameraActive)
        #expect(h.pose.stopCount >= 1)
        #expect(h.model.trackingStatus == .paused)
        #expect(h.model.statusLine == "Paused")
        #expect(h.model.lookSummary == .off)
    }

    @Test func aCalibrationRunningWhilePausedShowsCalibratingAndReturnsToPaused() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.startGateTest()
        h.reportRunning()
        #expect(h.model.trackingStatus == .calibrating)

        h.model.cancelGateTest()
        await h.model.cameraOperation?.value
        #expect(h.model.trackingStatus == .paused)
    }

    // MARK: Sensitivity (SPEC D31)

    @Test func theDefaultSensitivityGivesTheEngineDefaults() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        #expect(h.model.sensitivity == .default)
        #expect(h.engine.lastRecorder?.settings == .default)
    }

    @Test func changingTheSensitivitySavesItAndRebuildsTheDeciderWithTheMappedSettings() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let recorders = h.engine.recorders.count

        h.model.setSensitivity(SwitchSensitivity(dwell: 0.8, confidenceLevel: 4))

        let settings = try #require(h.engine.lastRecorder?.settings)
        #expect(h.engine.recorders.count == recorders + 1)
        #expect(settings.dwell == 0.8)
        #expect(settings.enterMargin == 0.45)
        #expect(settings.stayMargin == 0.225)
        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.8, confidenceLevel: 4))
        let stored = h.defaults.data(forKey: "sway.switchSensitivity")
        #expect(stored != nil)
        #expect(h.relaunchedModel().sensitivity == SwitchSensitivity(dwell: 0.8, confidenceLevel: 4))
    }

    @Test func theSameSensitivityAgainRebuildsNothing() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let recorders = h.engine.recorders.count

        h.model.setSensitivity(.default)

        #expect(h.engine.recorders.count == recorders)
        #expect(h.defaults.data(forKey: "sway.switchSensitivity") == nil)
    }

    @Test func outOfRangeSensitivityIsClamped() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setSensitivity(SwitchSensitivity(dwell: 99, confidenceLevel: -3))

        #expect(h.model.sensitivity.dwell == SwitchSensitivity.dwellRange.upperBound)
        #expect(h.model.sensitivity.confidenceLevel == 0)
    }

    @Test func storedSensitivityOutsideTheRangesIsClampedAndGarbageIsIgnored() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.defaults.set(Data(#"{"dwell": 50, "confidenceLevel": 9}"#.utf8), forKey: "sway.switchSensitivity")
        let clamped = h.relaunchedModel().sensitivity
        #expect(clamped.dwell == SwitchSensitivity.dwellRange.upperBound)
        #expect(clamped.confidenceLevel == SwitchSensitivity.confidenceMargins.count - 1)

        h.defaults.set(Data("nope".utf8), forKey: "sway.switchSensitivity")
        #expect(h.relaunchedModel().sensitivity == .default)
    }

    @Test func theEnterMarginReachesTheLoopsLookCheck() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.setSensitivity(SwitchSensitivity(dwell: 0.4, confidenceLevel: 4))
        #expect(h.model.enterMargin == 0.45)
    }
}
