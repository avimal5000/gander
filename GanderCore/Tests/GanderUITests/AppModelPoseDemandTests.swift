import Foundation
import GanderModels
import Testing

@testable import GanderUI

/// CONTRACT 6.5.5 item 2: the model tells the pose source how much frame rate it needs (SPEC D45).
@MainActor
@Suite("AppModel pose demand")
struct AppModelPoseDemandTests {
    /// A calibrated model with Tracking on, the camera running, and the first focused-display poll done.
    private func trackingHarness(trusted: Bool = true) async -> Harness {
        let h = Harness.make(trusted: trusted, calibrated: true)
        await h.startTracking()
        await h.settlePoll()
        return h
    }

    // MARK: Tracking

    @Test func plainTrackingAsksForTheAdaptiveRateOnceAfterTheStart() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        #expect(h.pose.demandCalls == [FakePoseSource.DemandCall(demand: .adaptive, startsSoFar: 1)])
    }

    @Test func nothingIsSentBeforeTheCameraRuns() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setFocusLock(true)
        h.model.setFocusLock(false)

        #expect(h.pose.demandCalls.isEmpty, "A start resets the source anyway, and says what is needed after it")
    }

    @Test func everyStartSaysWhatIsNeededAgainEvenWhenItIsTheSame() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        await h.model.enqueueCameraWork { await $0.restartPoseSource() }.value

        #expect(h.pose.startCount == 2)
        #expect(
            h.pose.demandCalls == [
                FakePoseSource.DemandCall(demand: .adaptive, startsSoFar: 1),
                FakePoseSource.DemandCall(demand: .adaptive, startsSoFar: 2),
            ])
    }

    @Test func samplesNeverCauseDemandCalls() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let calls = h.pose.demandCalls.count

        h.run(frames: 60, dt: 1.0 / 15)
        h.run(frames: 30, dt: 1.0 / 15, face: false)

        #expect(h.pose.demandCalls.count == calls)
    }

    // MARK: Reduced

    @Test func focusLockAsksForTheReducedRateAndUnlockingRestoresTheAdaptiveOne() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.model.setFocusLock(true)
        #expect(h.pose.demands == [.adaptive, .reduced])
        h.model.setFocusLock(true)
        #expect(h.pose.demands == [.adaptive, .reduced], "The same demand is not sent again")

        h.model.setFocusLock(false)
        #expect(h.pose.demands == [.adaptive, .reduced, .adaptive])
    }

    @Test func missingAccessibilityAsksForTheReducedRateUntilItIsGranted() async {
        let h = await trackingHarness(trusted: false)
        defer { h.tearDown() }
        #expect(h.model.trackingStatus == .needsAccessibility)
        #expect(h.pose.demands == [.adaptive, .reduced])

        h.focus.setTrusted(true)
        h.model.trackingTick()
        await h.settlePoll()

        #expect(h.model.trackingStatus == .noFace, "Running and trusted; no sample has arrived")
        #expect(h.pose.demands == [.adaptive, .reduced, .adaptive])
    }

    @Test func accessibilityGoingAwayLowersTheRate() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.focus.setTrusted(false)
        h.model.trackingTick()
        await h.settlePoll()

        #expect(h.model.trackingStatus == .needsAccessibility)
        #expect(h.pose.demands.last == .reduced)
    }

    // MARK: Full

    @Test func theGateTestAsksForTheFullRateAndTheEndGivesTheAdaptiveRateBack() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.model.gateConfiguration = GateTestConfiguration(rounds: 1, holdDuration: 3)

        await h.model.startGateTest()
        h.reportRunning()
        #expect(h.model.gateRunState == .running)
        #expect(h.pose.demandCalls.last == FakePoseSource.DemandCall(demand: .full, startsSoFar: 2))

        h.model.cancelGateTest()
        await h.model.cameraOperation?.value
        h.reportRunning()

        #expect(h.pose.startCount == 3, "Back to the tracking configuration, without landmarks")
        #expect(h.pose.demandCalls.last == FakePoseSource.DemandCall(demand: .adaptive, startsSoFar: 3))
    }

    @Test func theCameraCheckAndTheCalibrationInSetupAskForTheFullRate() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.openSetup()
        await h.model.cameraOperation?.value
        #expect(h.model.isSetupUsingCamera)
        #expect(h.pose.demands.last == .full)

        h.model.closeSetup()
        #expect(h.pose.demands.last == .adaptive)
    }

    @Test func setupAloneStartsTheCameraAtTheFullRate() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        await h.openSetupOnCameraCheck()

        #expect(h.pose.demandCalls == [FakePoseSource.DemandCall(demand: .full, startsSoFar: 1)])
    }

    @Test func thePoseDebugWindowAsksForTheFullRateWhileItShowsLiveContent() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.model.noteWindowRequested(GanderWindowID.poseDebug)
        h.model.setPoseDebugVisible(true)
        #expect(h.pose.demands.last == .full)

        h.model.setPoseDebugVisible(false)  // Minimized, covered closed, or closing.
        #expect(h.pose.demands.last == .adaptive)

        h.model.setPoseDebugVisible(true)
        #expect(h.pose.demands.last == .full)
    }

    @Test func aPoseDebugWindowNobodyAskedForIsIgnored() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        // The copy SwiftUI opens at launch, which the launch guard closes unseen.
        h.model.setPoseDebugVisible(true)

        #expect(!h.model.poseDebugVisible)
        #expect(h.pose.demands == [.adaptive])
    }

    @Test func theFocusTestWindowAsksForTheFullRate() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.model.noteWindowRequested(GanderWindowID.focusTest)
        h.model.startFocusTest()
        #expect(h.pose.demands.last == .full)

        h.model.stopFocusTest()
        #expect(h.pose.demands.last == .adaptive)
    }

    @Test func theFullRateBeatsTheReducedOne() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.model.setFocusLock(true)
        #expect(h.pose.demands.last == .reduced)

        h.model.noteWindowRequested(GanderWindowID.poseDebug)
        h.model.setPoseDebugVisible(true)
        #expect(h.pose.demands.last == .full, "Pose Debug needs live numbers even with Focus Lock on")

        h.model.setPoseDebugVisible(false)
        #expect(h.pose.demands.last == .reduced)
    }

    @Test func stoppingTheCameraForgetsTheDemandSoTheNextStartSendsIt() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(false)
        h.model.setFocusLock(true)
        #expect(h.pose.demands == [.adaptive], "No stream, nothing sent")

        await h.model.setTrackingEnabled(true)
        #expect(h.pose.demandCalls.last == FakePoseSource.DemandCall(demand: .reduced, startsSoFar: 2))
    }
}
