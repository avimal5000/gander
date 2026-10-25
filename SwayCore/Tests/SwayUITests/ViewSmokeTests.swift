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

    @Test func emptyPlotsDoNotCrash() {
        #expect(renders(ScatterPlotView(points: [], clusters: []), width: 400, height: 300))
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(renders(PosePlotView(model: h.model), width: 500, height: 320))
    }
}
