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

    @Test func menuContentRendersOffAndLive() {
        let off = Harness.make()
        defer { off.tearDown() }
        #expect(renders(MenuContentView(model: off.model), width: 300, height: 400))

        let live = Harness.make()
        defer { live.tearDown() }
        live.reportRunning()
        live.run(frames: 10, dt: 0.1)
        #expect(renders(MenuContentView(model: live.model), width: 300, height: 400))
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
            let h = Harness.make(authorization: authorization)
            defer { h.tearDown() }
            await h.model.setLiveEnabled(true)
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
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 400), "Calibrated, camera off")

        await h.startLive()
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
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 500), "With a logged switch")

        h.model.layoutDidChange(Fixtures.threeDisplays)
        #expect(h.model.isCalibrationStale)
        #expect(renders(SwitchPreviewView(model: h.model), width: 520, height: 500), "Stale")
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
}
