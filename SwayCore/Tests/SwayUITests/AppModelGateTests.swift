import AppKit
import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel gate test")
struct AppModelGateTests {
    /// Starts a gate test on a fresh harness and reports the camera as running, leaving the first settle phase open.
    private func startedGate(
        layout: DisplayLayout = Fixtures.twoDisplays, rounds: Int = 2, hold: TimeInterval = 3,
        liveBefore: Bool = false
    ) async -> Harness {
        let h = Harness.make(layout: layout)
        h.model.gateConfiguration = GateTestConfiguration(rounds: rounds, holdDuration: hold)
        if liveBefore {
            await h.model.setLiveEnabled(true)
            h.reportRunning()
        }
        await h.model.startGateTest()
        // With Live already on, the gate test restarts the source with landmarks, so it reports running again.
        h.reportRunning()
        return h
    }

    /// Feeds samples every 0.25 s, aiming at whichever display the overlay shows, until the run ends.
    private func runToCompletion(_ h: Harness) {
        var frames = 0
        while h.model.gateRunState == .running, frames < 2000 {
            h.clock.advance(by: 0.25)
            let target = h.overlay.lastProgress?.display.id
            h.feed(yaw: target == Fixtures.left.id ? -20 : 20)
            h.model.gateTick()
            frames += 1
        }
    }

    // MARK: Happy path

    @Test func aFullRunProducesAnAnalysisFromTheLabeledTrace() async throws {
        let h = await startedGate()
        defer { h.tearDown() }

        #expect(h.model.gateRunState == .running)
        #expect(h.pose.startCount == 1)
        #expect(h.overlay.lastProgress?.display.id == Fixtures.left.id)
        #expect(h.overlay.lastProgress?.phase == .settle)

        runToCompletion(h)

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateProgress == nil)
        #expect(h.model.isShowingReport)
        #expect(h.model.analysis == Fixtures.analysis())
        #expect(h.model.analysisSource == .gateTest)
        #expect(h.model.reportFeatureSet == .visionAngles)
        #expect(!h.overlay.isShowing)

        let trace = try #require(h.analyzer.analyzedTraces.first)
        #expect(h.analyzer.analyzedTraces.count == 1)
        #expect(h.analyzer.analyzedThresholds == [.default])
        #expect(trace.segments.map(\.round) == [1, 1, 2, 2])
        #expect(
            trace.segments.map(\.displayID) == [
                Fixtures.left.id, Fixtures.right.id, Fixtures.left.id, Fixtures.right.id,
            ])
        #expect(trace.segments.allSatisfy { $0.samples.count == 12 })
        #expect(trace.segments[0].samples.allSatisfy { $0.pose?.yaw == -20 })
        #expect(trace.segments[1].samples.allSatisfy { $0.pose?.yaw == 20 })
        #expect(trace.layout == Fixtures.twoDisplays)
        #expect(trace.cameraName == Fixtures.builtInCamera.name)
        #expect(trace.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(h.model.analysisTrace == trace)
    }

    @Test func theOverlayFollowsTheStepsAndPhases() async {
        let h = await startedGate(rounds: 1, hold: 3)
        defer { h.tearDown() }

        runToCompletion(h)

        let visited = h.overlay.presented.map { "\($0.display.id.rawValue):\($0.phase)" }
        #expect(visited.first == "display-left:settle")
        #expect(visited.contains("display-left:hold"))
        #expect(visited.contains("display-right:settle"))
        #expect(visited.last == "display-right:hold")
        #expect(h.overlay.dismissCount >= 1)
    }

    @Test func theTraceIsSavedInDebugBuildsAndAnErrorIsShown() async {
        #if DEBUG
        let h = await startedGate(rounds: 1)
        defer { h.tearDown() }
        runToCompletion(h)
        #expect(h.store.saved.count == 1)
        if case .saved(let url) = h.model.traceSaveStatus {
            #expect(url.lastPathComponent == "trace-1.json")
        } else {
            Issue.record("Expected a saved trace, got \(h.model.traceSaveStatus)")
        }

        let failing = await startedGate(rounds: 1)
        defer { failing.tearDown() }
        failing.store.setSaveError(.io("disk full"))
        runToCompletion(failing)
        #expect(failing.model.analysis != nil)
        if case .failed(let message) = failing.model.traceSaveStatus {
            #expect(message.contains("disk full"))
        } else {
            Issue.record("Expected a save failure, got \(failing.model.traceSaveStatus)")
        }
        #endif
    }

    @Test func theCameraRunsOnlyForTheTestWhenLiveWasOff() async {
        let h = await startedGate(rounds: 1)
        defer { h.tearDown() }
        #expect(h.model.isCameraActive)

        runToCompletion(h)
        await h.model.cameraOperation?.value

        #expect(!h.model.isCameraActive)
        #expect(h.pose.stopCount >= 1)
        #expect(!h.model.liveEnabled)
    }

    @Test func theCameraStaysOnAfterTheTestWhenLiveWasOn() async {
        let h = await startedGate(rounds: 1, liveBefore: true)
        defer { h.tearDown() }

        runToCompletion(h)
        await h.model.cameraOperation?.value

        #expect(h.model.isCameraActive)
        #expect(h.model.liveEnabled)
        #expect(h.model.analysis != nil)
        // Live, then the gate test's restart with landmarks, then Live again without them.
        #expect(h.pose.configurations.map(\.includeLandmarks) == [false, true, false])
    }

    // MARK: Landmarks (SPEC D15)

    @Test func theGateTestTurnsLandmarksOnAndLiveAfterwardsRunsWithoutThem() async {
        let h = await startedGate(rounds: 1)
        defer { h.tearDown() }
        #expect(h.pose.configurations.map(\.includeLandmarks) == [true])

        runToCompletion(h)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)

        await h.model.setLiveEnabled(true)
        #expect(h.pose.configurations.map(\.includeLandmarks) == [true, false])
        #expect(h.model.activeConfiguration?.includeLandmarks == false)
    }

    @Test func landmarksAreOnFromTheCameraStartPhase() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.startGateTest()

        #expect(h.model.gateRunState == .startingCamera)
        #expect(h.pose.configurations == [PoseSourceConfiguration(cameraDeviceID: nil, includeLandmarks: true)])
    }

    @Test func liveAloneNeverAsksForLandmarks() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.setLiveEnabled(true)

        #expect(h.pose.configurations.map(\.includeLandmarks) == [false])
    }

    @Test func aGateTestStartedWhileLiveRunsRestartsTheSourceWithLandmarks() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }
        await h.model.setLiveEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.model.gateConfiguration = GateTestConfiguration(rounds: 1, holdDuration: 3)

        await h.model.startGateTest()
        let running = await waitUntil { h.model.gateRunState == .running }

        #expect(running)
        #expect(h.pose.configurations.map(\.includeLandmarks) == [false, true])
        #expect(h.pose.stopCount >= 1)
        // The restart replaces the stream, so the test's frames come from the landmark stream only.
        #expect(h.model.liveEnabled)
    }

    @Test func aCancelledGateTestPutsLiveBackWithoutLandmarks() async {
        let h = await startedGate(liveBefore: true)
        defer { h.tearDown() }
        #expect(h.model.activeConfiguration?.includeLandmarks == true)

        h.model.cancelGateTest(reason: nil)
        await h.model.cameraOperation?.value

        #expect(h.model.isCameraActive)
        #expect(h.model.liveEnabled)
        #expect(h.model.activeConfiguration?.includeLandmarks == false)
        #expect(h.pose.configurations.map(\.includeLandmarks) == [false, true, false])
    }

    // MARK: Cancel and failure

    @Test func escapeCancelsRemovesOverlaysAndRestoresTheCamera() async {
        let h = await startedGate()
        defer { h.tearDown() }
        h.run(frames: 4)
        #expect(h.overlay.isShowing)

        h.overlay.pressEscape()
        await h.model.cameraOperation?.value

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateProgress == nil)
        #expect(!h.overlay.isShowing)
        #expect(h.model.analysis == nil)
        #expect(h.analyzer.analyzedTraces.isEmpty)
        #expect(h.model.gateMessage == .info("Gate test cancelled."))
        #expect(!h.model.isCameraActive)
        #expect(h.store.saved.isEmpty)
    }

    @Test func cancellingTheButtonWayAlsoWorksAndIgnoresLaterSamples() async {
        let h = await startedGate()
        defer { h.tearDown() }
        h.model.cancelGateTest(reason: "Gate test cancelled.")
        h.run(frames: 40)
        #expect(h.model.gateRunState == .idle)
        #expect(h.analyzer.analyzedTraces.isEmpty)
        #expect(!h.overlay.isShowing)
    }

    @Test func cancelDoesNothingWhenNoTestIsRunning() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.cancelGateTest(reason: "x")
        #expect(h.model.gateMessage == nil)
        #expect(h.overlay.dismissCount == 0)
    }

    @Test func aCameraInterruptionAbortsTheRun() async {
        let h = await startedGate()
        defer { h.tearDown() }
        h.run(frames: 8)

        h.model.handle(.status(.interrupted("Camera disconnected")))
        await h.model.cameraOperation?.value

        #expect(h.model.gateRunState == .idle)
        #expect(!h.overlay.isShowing)
        #expect(h.model.analysis == nil)
        #expect(h.model.gateMessage?.kind == .error)
        #expect(h.model.gateMessage?.text.contains("interrupted") == true)
    }

    @Test func aSuspendedCameraAlsoAbortsTheRun() async {
        let h = await startedGate()
        defer { h.tearDown() }
        h.model.handle(.status(.suspended(.screenLocked)))
        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateMessage?.kind == .error)
    }

    @Test func theRealCamerasStartSequenceBeginsTheRunOnce() async {
        // LivePoseSource reports `.starting` itself; the camera may then stall once before its first frame and
        // reports `.running` again when frames arrive. Only the first `.running` begins the run, and the repeat
        // does not restart or abort it.
        let h = Harness.make()
        defer { h.tearDown() }
        let camera = Fixtures.builtInCamera

        await h.model.startGateTest()
        h.model.handle(.status(.starting))
        h.model.handle(.status(.interrupted("No frames from the camera")))
        #expect(h.model.gateRunState == .startingCamera)
        #expect(!h.overlay.isShowing)

        h.model.handle(.status(.running(camera)))
        #expect(h.model.gateRunState == .running)
        let progress = h.overlay.lastProgress
        #expect(progress?.display.id == Fixtures.left.id)

        h.run(frames: 4)
        h.model.handle(.status(.running(camera)))
        #expect(h.model.gateRunState == .running)
        #expect(h.model.gateMessage == nil)
        #expect(h.overlay.isShowing)
    }

    @Test func aFailureWhileTheCameraStartsAbortsWithItsReason() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.startGateTest()
        h.model.handle(.status(.starting))
        h.model.handle(.status(.failed(.runtimeFailure("sensor died"))))
        await h.model.cameraOperation?.value

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateMessage?.kind == .error)
        #expect(h.model.gateMessage?.text.contains("sensor died") == true)
        #expect(!h.overlay.isShowing)
        #expect(!h.model.liveEnabled)
    }

    @Test func aCameraThatNeverStartsTimesOut() async {
        let h = Harness.make()
        defer { h.tearDown() }

        await h.model.startGateTest()
        #expect(h.model.gateRunState == .startingCamera)
        #expect(!h.overlay.isShowing)

        h.clock.set(9)
        h.model.gateTick()
        #expect(h.model.gateRunState == .startingCamera)

        h.clock.set(10)
        h.model.gateTick()
        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateMessage?.kind == .error)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)
    }

    @Test func aFailedStartShowsAnErrorAndRestoresTheIdleState() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.pose.setStartError(.deviceUnavailable("in use by another app"))

        await h.model.startGateTest()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateMessage == .error("The camera could not start: in use by another app."))
        #expect(!h.overlay.isShowing)
    }

    @Test func changingTheDisplayLayoutCancelsTheRun() async {
        let h = await startedGate()
        defer { h.tearDown() }

        h.model.layoutDidChange(Fixtures.threeDisplays)

        #expect(h.model.gateRunState == .idle)
        #expect(!h.overlay.isShowing)
        #expect(h.model.layout == Fixtures.threeDisplays)
        #expect(h.model.gateMessage?.text.contains("display arrangement") == true)
    }

    @Test func layoutChangesFlowThroughTheDisplayStream() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.displays.change(to: Fixtures.threeDisplays)
        let updated = await waitUntil { h.model.layout == Fixtures.threeDisplays }
        #expect(updated)
        #expect(h.model.exceedsTrackedDisplays)
    }

    @Test func losingFocusDuringTheRunCancelsIt() async {
        let h = await startedGate()
        defer { h.tearDown() }

        h.notifications.post(name: NSApplication.didResignActiveNotification, object: nil)

        #expect(h.model.gateRunState == .idle)
        #expect(!h.overlay.isShowing)
        #expect(h.model.gateMessage?.kind == .info)
    }

    @Test func losingFocusOutsideARunChangesNothing() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.notifications.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(h.model.gateMessage == nil)
    }

    // MARK: Preconditions

    @Test func theTestNeedsAtLeastTwoDisplays() async {
        let h = Harness.make(layout: Fixtures.oneDisplay)
        defer { h.tearDown() }
        #expect(!h.model.canRunGateTest)

        await h.model.startGateTest()

        #expect(h.model.gateRunState == .idle)
        #expect(h.pose.startCount == 0)
        #expect(h.model.gateMessage?.kind == .error)
        #expect(h.model.gateMessage?.text.contains("at least 2 displays") == true)
    }

    @Test func moreDisplaysThanTheLimitAreFlaggedButStillMeasured() async {
        let h = await startedGate(layout: Fixtures.threeDisplays, rounds: 1)
        defer { h.tearDown() }
        #expect(h.model.exceedsTrackedDisplays)
        #expect(Fixtures.threeDisplays.displays.count > SwayPolicy.maxTrackedDisplays)

        runToCompletion(h)

        let trace = h.analyzer.analyzedTraces.first
        #expect(trace?.segments.map(\.displayID) == [Fixtures.left.id, Fixtures.right.id, Fixtures.far.id])
    }

    @Test func twoDisplaysAreWithinTheTrackedLimit() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(!h.model.exceedsTrackedDisplays)
        #expect(h.model.canRunGateTest)
    }

    @Test func aDisplayWithoutAScreenBlocksTheStart() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.overlay.unavailable = [Fixtures.right.id]

        await h.model.startGateTest()

        #expect(h.model.gateRunState == .idle)
        #expect(h.pose.startCount == 0)
        #expect(h.model.gateMessage?.text.contains("Right") == true)
    }

    @Test func aSecondStartWhileRunningIsIgnored() async {
        let h = await startedGate()
        defer { h.tearDown() }
        await h.model.startGateTest()
        #expect(h.pose.startCount == 1)
        #expect(h.model.gateRunState == .running)
    }

    @Test func theFirstGateTestAsksForCameraPermissionThenRunsOnceGranted() async {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }

        await h.model.startGateTest()
        #expect(h.model.permissionPrompt == .explanation)
        #expect(h.model.gateRunState == .idle)
        #expect(h.pose.startCount == 0)
        #expect(h.model.gateMessage == nil)

        await h.model.continueAfterPermissionExplanation()
        #expect(h.camera.requestCount == 1)
        #expect(h.pose.startCount == 1)
        #expect(h.model.gateRunState == .startingCamera)
        h.reportRunning()
        #expect(h.model.gateRunState == .running)
    }

    // MARK: After the run

    @Test func runAgainReturnsToTheSetupForm() async {
        let h = await startedGate(rounds: 1)
        defer { h.tearDown() }
        runToCompletion(h)
        #expect(h.model.isShowingReport)

        h.model.showGateSetup()
        #expect(!h.model.isShowingReport)
        #expect(h.model.analysis != nil)
    }
}
