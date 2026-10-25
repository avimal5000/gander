import SwayModels
import SwiftUI
import Testing

@testable import SwayUI

/// Renders each screen once, offscreen and in memory, to catch view-construction crashes (empty chart domains,
/// bad bindings). Nothing is displayed or written.
@MainActor
@Suite("View smoke tests")
struct ViewSmokeTests {
    private func renders(_ view: some View, width: CGFloat = 700, height: CGFloat = 700) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 1
        return renderer.cgImage != nil
    }

    @Test func menuContentRendersInEveryBannerState() async {
        let first = Harness.make()
        defer { first.tearDown() }
        #expect(first.model.menuBanner == .firstSetup)
        #expect(renders(MenuContentView(model: first.model), width: 300, height: 500), "First setup")

        let tracking = Harness.make(calibrated: true)
        defer { tracking.tearDown() }
        await tracking.startTracking()
        tracking.run(frames: 10, dt: 0.1)
        #expect(tracking.model.menuBanner == nil)
        #expect(renders(MenuContentView(model: tracking.model), width: 300, height: 500), "Tracking")

        let noAccess = Harness.make(trusted: false, calibrated: true)
        defer { noAccess.tearDown() }
        await noAccess.startTracking()
        #expect(noAccess.model.menuBanner == .needsAccessibility)
        #expect(renders(MenuContentView(model: noAccess.model), width: 300, height: 500), "Needs Accessibility")

        let unknown = Harness.make(
            layout: Fixtures.threeDisplays, trackingSaved: true,
            seed: {
                Harness.seedLibrary([Fixtures.profile()], into: $0)
            })
        defer { unknown.tearDown() }
        #expect(unknown.model.menuBanner == .needsCalibration)
        #expect(renders(MenuContentView(model: unknown.model), width: 300, height: 500), "Needs calibration")

        let failed = Harness.make(calibrated: true, hotKeys: failingHotKeys())
        defer { failed.tearDown() }
        #expect(failed.model.menuBanner == .shortcut("The Focus Lock shortcut could not be set up."))
        #expect(renders(MenuContentView(model: failed.model), width: 300, height: 500), "Shortcut message")
    }

    private func failingHotKeys() -> FakeHotKeys {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(HotKeyShortcut.focusLockDefault, .registrationFailed(-1))]
        return hotKeys
    }

    @Test func poseDebugRendersWithoutAndWithAnAnalysis() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(renders(PoseDebugView(model: h.model)))

        h.reportRunning()
        h.run(frames: 30, dt: 0.1, yaw: 12)
        #expect(renders(PoseDebugView(model: h.model)))

        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)
        h.run(frames: 5, dt: 0.1, yaw: -12)
        #expect(renders(PoseDebugView(model: h.model)))
    }

    @Test func gateWindowRendersSetupRunningAndReport() async {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(renders(GateTestView(model: h.model)))

        await h.model.startGateTest()
        #expect(renders(GateTestView(model: h.model)))
        h.reportRunning()
        #expect(renders(GateTestView(model: h.model)))
        h.model.cancelGateTest()

        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)
        h.model.isShowingReport = true
        #expect(renders(GateTestView(model: h.model)))
    }

    @Test func permissionBannersRenderForEveryPrompt() async {
        for authorization in [CameraAuthorization.notDetermined, .denied, .restricted] {
            let h = Harness.make(authorization: authorization, calibrated: true)
            defer { h.tearDown() }
            await h.model.setTrackingEnabled(true)
            #expect(h.model.permissionPrompt != nil)
            #expect(renders(CameraPermissionView(model: h.model), width: 300, height: 300))
        }
    }

    @Test func overlayContentRendersInBothPhases() {
        for phase in [GateProgress.Phase.settle, .hold] {
            let progress = GateProgress(
                phase: phase, stepNumber: 1, stepCount: 4, round: 1, rounds: 2, displayNumber: 1, displayCount: 2,
                display: Fixtures.left, phaseElapsed: 0.5, phaseDuration: 1.5, recordedSamples: 0, recordedFaces: 0
            )
            #expect(renders(GateOverlayView(model: GateOverlayModel(progress: progress)), width: 800, height: 450))
        }
    }

    @Test func switchPreviewRendersInEveryState() async {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 400), "Not calibrated")

        h.openTrace()
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 400), "Calibrated, tracking off")

        await h.startTracking()
        h.engine.script.set { sample, _ in
            Fixtures.decision(
                switchTo: sample.timestamp > 2 ? Fixtures.right.id : nil,
                phase: sample.timestamp > 2
                    ? .coolingDown(until: 3) : .dwelling(display: Fixtures.right.id, progress: 0.5),
                classification: Fixtures.classification(best: Fixtures.right.id))
        }
        h.model.handle(.sample(Fixtures.sample(at: 1)))
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 400), "Dwelling")
        h.model.handle(.sample(Fixtures.sample(at: 3)))
        await h.settleSwitch()
        #expect(!h.model.switchLog.isEmpty)
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 500), "With a logged switch")

        h.model.setFocusLock(true)
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 500), "Focus Lock on")

        h.model.layoutDidChange(Fixtures.threeDisplays)
        #expect(h.model.activeCalibration == nil)
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 500), "No calibration fits")
    }

    @Test func focusTestRendersGrantedNotGrantedAndBusy() async {
        let denied = Harness.make(trusted: false)
        defer { denied.tearDown() }
        #expect(renders(FocusTestView(model: denied.model)))

        let h = Harness.make()
        defer { h.tearDown() }
        h.focus.setWindows([Fixtures.left.id: Fixtures.window()])
        h.model.noteWindowRequested(SwayWindowID.focusTest)
        h.model.startFocusTest()
        await h.model.focusPollTask?.value
        #expect(renders(FocusTestView(model: h.model)))

        h.model.focusAfterDelay(Fixtures.left.id)
        #expect(renders(FocusTestView(model: h.model)), "Counting down")
        h.model.stopFocusTest()
    }

    @Test func theReportShowsTheCalibrationOutcome() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        #expect(renders(GateTestView(model: h.model)))

        h.engine.setFitResult(.failure(.tooFewDisplays))
        h.openTrace(name: "second.json")
        #expect(h.model.calibrationMessage != nil)
        #expect(renders(GateTestView(model: h.model)))
    }

    @Test func emptyPlotsDoNotCrash() {
        #expect(renders(ScatterPlotView(points: [], clusters: []), width: 400, height: 300))
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(renders(PosePlotView(model: h.model), width: 500, height: 320))
    }

    // MARK: Setup and Settings (M5)

    @Test func setupRendersEveryStep() async {
        let access = Harness.make(authorization: .notDetermined)
        defer { access.tearDown() }
        access.openSetup()
        #expect(access.model.setupFlow?.step == .cameraAccess)
        #expect(renders(SetupView(model: access.model), width: 520, height: 420), "Camera access, explanation")
        access.camera.setAuthorizationAfterRequest(.denied)
        await access.model.requestCameraAccessFromSetup()
        #expect(renders(SetupView(model: access.model), width: 520, height: 420), "Camera access, denied")
        let restricted = Harness.make(authorization: .restricted)
        defer { restricted.tearDown() }
        restricted.openSetup()
        #expect(renders(SetupView(model: restricted.model), width: 520, height: 420), "Camera access, restricted")

        let accessibility = Harness.make(trusted: false)
        defer { accessibility.tearDown() }
        accessibility.openSetup()
        #expect(accessibility.model.setupFlow?.step == .accessibility)
        #expect(renders(SetupView(model: accessibility.model), width: 520, height: 420), "Accessibility")

        let check = Harness.make()
        defer { check.tearDown() }
        check.openSetup()
        await check.model.cameraOperation?.value
        #expect(renders(SetupView(model: check.model), width: 520, height: 420), "Camera check, starting")
        check.reportRunning()
        check.feed()
        #expect(renders(SetupView(model: check.model), width: 520, height: 420), "Camera check, good")
        check.clock.advance(by: 1)
        check.feed(face: false)
        #expect(renders(SetupView(model: check.model), width: 520, height: 420), "Camera check, no face")

        await check.model.startCalibration()
        #expect(check.model.setupFlow?.step == .calibrating)
        #expect(renders(SetupView(model: check.model), width: 520, height: 420), "Calibrating")
        check.runCalibration()
        #expect(check.model.setupFlow?.step == .result)
        #expect(renders(SetupView(model: check.model), width: 520, height: 420), "Result, good")

        let failed = Harness.make()
        defer { failed.tearDown() }
        failed.engine.setFitResult(.failure(.tooFewDisplays))
        await failed.openSetupOnCameraCheck()
        await failed.completeCalibration()
        #expect(renders(SetupView(model: failed.model), width: 520, height: 420), "Result, failed")
    }

    @Test func setupRendersTheCameraCheckProblems() async {
        let one = Harness.make(layout: Fixtures.oneDisplay)
        defer { one.tearDown() }
        await one.openSetupOnCameraCheck()
        #expect(renders(SetupView(model: one.model), width: 520, height: 420), "One display")

        let failing = Harness.make()
        defer { failing.tearDown() }
        failing.pose.setStartError(.noDevice)
        failing.openSetup()
        await failing.model.cameraOperation?.value
        #expect(renders(SetupView(model: failing.model), width: 520, height: 420), "Camera failed")

        let busy = Harness.make()
        defer { busy.tearDown() }
        await busy.openSetupOnCameraCheck()
        busy.model.handle(.status(.interrupted("Camera is in use by another app")))
        #expect(renders(SetupView(model: busy.model), width: 520, height: 420), "Camera interrupted")

        let closed = Harness.make()
        defer { closed.tearDown() }
        #expect(renders(SetupView(model: closed.model), width: 520, height: 420), "Window closed")
    }

    @Test func settingsRendersInEveryState() async {
        let empty = Harness.make()
        defer { empty.tearDown() }
        #expect(renders(SettingsView(model: empty.model), width: 520, height: 640), "No calibrations")

        let full = Harness.make(calibrated: true, calibrationCameras: ["FaceTime HD Camera", "Logitech C922", nil])
        defer { full.tearDown() }
        full.loginItem.status = .requiresApproval
        full.openSettings()
        #expect(renders(SettingsView(model: full.model), width: 520, height: 640), "Calibrations and approval")

        full.model.beginShortcutRecording()
        full.keyMonitor.press(0, [], characters: "a")
        #expect(renders(SettingsView(model: full.model), width: 520, height: 640), "Recording with a hint")
        full.model.cancelShortcutRecording()

        full.loginItem.status = .unavailable("macOS can't find this copy of Sway.")
        full.loginItem.error = LoginItemError(message: "Nope.")
        full.model.setOpensAtLogin(true)
        full.model.setHoldTime(1.2)
        full.model.setSwitchConfidence(4)
        full.model.clearFocusLockShortcut()
        #expect(renders(SettingsView(model: full.model), width: 520, height: 640), "Unavailable, error, no shortcut")

        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(HotKeyShortcut.focusLockDefault, .shortcutInUse)]
        let refused = Harness.make(calibrated: true, hotKeys: hotKeys)
        defer { refused.tearDown() }
        #expect(refused.model.shortcutMessage != nil)
        #expect(renders(SettingsView(model: refused.model), width: 520, height: 640), "Shortcut refused")
    }

    @Test func menuRendersTheCameraSpecificBanner() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        h.model.refreshAccessibilityTrust()
        await h.model.selectCamera(Fixtures.externalCamera.id)
        #expect(h.model.menuBanner == .needsCameraCalibration("Logitech C922"))
        #expect(renders(MenuContentView(model: h.model), width: 300, height: 520))
    }
}
