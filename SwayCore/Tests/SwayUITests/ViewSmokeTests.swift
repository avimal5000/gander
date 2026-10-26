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

    // MARK: Design pass (M6)

    /// Renders `view` at one point per pixel and reads back the opacity of pixel (x, y), counted from the top left.
    private func alphaReader(of view: some View, width: Int, height: Int) -> ((Int, Int) -> Double)? {
        let renderer = ImageRenderer(content: view.frame(width: CGFloat(width), height: CGFloat(height)))
        renderer.scale = 1
        guard let image = renderer.cgImage,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Copied out: the context owns the pixels and goes away when this returns.
        let bytes = Array(
            UnsafeBufferPointer(
                start: data.bindMemory(to: UInt8.self, capacity: width * height * 4), count: width * height * 4))
        return { x, y in Double(bytes[(y * width + x) * 4 + 3]) / 255 }
    }

    @Test func theSwingMarkDrawsInsideItsFrameInEveryFraming() throws {
        let fitted = try #require(
            alphaReader(of: SwayMark(color: SwayPalette.green), width: 64, height: 64), "Fitted")
        #expect(fitted(32, 45) > 0.9, "The dip of the arc, in the middle")
        #expect(fitted(2, 2) == 0 && fitted(61, 61) == 0 && fitted(2, 61) == 0, "The corners are empty")

        let square = try #require(
            alphaReader(of: SwayMark(color: SwayPalette.green, framing: .unitSquare), width: 100, height: 100),
            "Unit square")
        #expect(square(24, 40) > 0.9, "The start point, where the geometry puts it")
        #expect(square(76, 40) > 0.9, "The end point")
        #expect(square(50, 63) > 0.9, "The bottom of the arc")
        #expect(square(5, 5) == 0 && square(94, 94) == 0)
    }

    /// Renders an AppKit view's layer tree at 1x and reads alpha at a pixel, (0, 0) at the top left.
    private func alphaReader(of view: NSView) -> ((Int, Int) -> Double)? {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        guard let layer = view.layer,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { return nil }
        layer.render(in: context)
        let bytes = Array(
            UnsafeBufferPointer(
                start: data.bindMemory(to: UInt8.self, capacity: width * height * 4), count: width * height * 4))
        return { x, y in Double(bytes[(y * width + x) * 4 + 3]) / 255 }
    }

    @Test func theEdgeGlowHasABorderAtTheEdgeAndAnEmptyMiddle() throws {
        let view = EdgeGlowView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        let glow = try #require(alphaReader(of: view))
        #expect(glow(0, 70) > 0.99 && glow(239, 70) > 0.99, "The 4 pt border on the left and right")
        #expect(glow(120, 0) > 0.99 && glow(120, 139) > 0.99, "On the top and bottom")
        #expect(glow(3, 70) > 0.99 && glow(4, 70) < 0.5, "The border is 4 pt wide")
        #expect(glow(5, 70) > glow(12, 70) && glow(234, 70) > glow(227, 70), "The side glows fade inward")
        #expect(glow(120, 5) > glow(120, 12) && glow(120, 134) > glow(120, 127), "So do the top and bottom ones")
        #expect(glow(14, 70) == 0 && glow(120, 70) == 0 && glow(120, 14) == 0, "Nothing past the glow")
    }

    @Test func theEdgeGlowFollowsItsFrameWhenThePanelMovesToAnotherDisplay() throws {
        let view = EdgeGlowView(frame: NSRect(x: 0, y: 0, width: 240, height: 140))
        view.setFrameSize(NSSize(width: 300, height: 200))
        let glow = try #require(alphaReader(of: view))
        #expect(glow(299, 100) > 0.99 && glow(150, 199) > 0.99, "The border moved to the new right and top edges")
        #expect(glow(239, 100) == 0, "Nothing left where the old right edge was")
    }

    @Test func theWelcomeStepRendersInLightAndDark() {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(h.model.setupFlow?.step == .welcome)

        #expect(renders(SetupView(model: h.model), width: 520, height: 420), "Welcome")
        #expect(
            renders(SetupView(model: h.model).environment(\.colorScheme, .dark), width: 520, height: 420),
            "Welcome, dark")
        #expect(renders(SetupWelcomeStep(model: h.model), width: 472, height: 372), "The step alone")
        #expect(renders(SetupHeader(step: .cameraCheck), width: 472, height: 60), "The shared header")
    }

    @Test func theAppearanceSectionRendersWithEveryChoice() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(renders(SettingsView(model: h.model), width: 520, height: 640), "Defaults")

        h.model.setAccentChoice(.system)
        h.model.setEdgeGlowEnabled(false)
        h.model.setFocusLockNoticeEnabled(false)
        #expect(renders(SettingsView(model: h.model), width: 520, height: 640), "Match macOS, both off")
        #expect(
            renders(SettingsView(model: h.model).environment(\.colorScheme, .dark), width: 520, height: 640),
            "Dark")
    }

    @Test func thePopoverRendersItsHeaderWithEveryAccent() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        for choice in AccentChoice.allCases {
            h.model.setAccentChoice(choice)
            #expect(renders(MenuContentView(model: h.model), width: 300, height: 500), "\(choice)")
        }
        #expect(MenuContentView.markSize == 16)
    }

    @Test func theOtherWindowsRenderWithTheSystemAccent() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.setAccentChoice(.system)

        #expect(renders(PoseDebugView(model: h.model)))
        #expect(renders(GateTestView(model: h.model)))
        #expect(renders(FocusTestView(model: h.model)))
        #expect(renders(SetupView(model: h.model), width: 520, height: 420))
    }

    @Test func theMenuBarLabelRendersEveryGlyph() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(renders(MenuBarLabel(model: h.model), width: 40, height: 24), "Paused")
        await h.startTracking()
        h.feed()
        #expect(renders(MenuBarLabel(model: h.model), width: 40, height: 24), "Tracking")
        h.model.setFocusLock(true)
        #expect(renders(MenuBarLabel(model: h.model), width: 40, height: 24), "Focus Lock")
        h.focus.setTrusted(false)
        h.model.refreshAccessibilityTrust()
        #expect(renders(MenuBarLabel(model: h.model), width: 40, height: 24), "Needs Accessibility")
    }
}
