import Foundation
import GanderModels

@testable import GanderUI

extension Harness {
    /// Runs a one-round gate test from start to finish: reports the camera running, then feeds a sample every
    /// 0.25 s aimed at whichever display the overlay shows.
    func completeGateRun() async {
        model.gateConfiguration = GateTestConfiguration(rounds: 1, holdDuration: 3)
        await model.startGateTest()
        reportRunning()
        var frames = 0
        while model.gateRunState == .running, frames < 2000 {
            clock.advance(by: 0.25)
            let target = overlay.lastProgress?.display.id
            feed(yaw: target == Fixtures.left.id ? -20 : 20)
            model.gateTick()
            frames += 1
        }
        await model.cameraOperation?.value
    }

    /// Opens a saved trace (the fake store serves `trace`), which fits a calibration profile.
    @discardableResult
    func openTrace(_ trace: PoseTrace = Fixtures.trace(), name: String = "saved.json") -> URL {
        let url = URL(fileURLWithPath: "/tmp/gander-ui-tests/\(name)")
        store.setLoadable(trace, at: url)
        model.openTrace(at: url)
        return url
    }

    /// Turns Tracking on, with the camera reported running. Seed a calibration first (`Harness.make(calibrated:)`
    /// or `openTrace()`) so the camera and the decider exist.
    func startTracking() async {
        await model.setTrackingEnabled(true)
        reportRunning()
    }

    /// Waits for the focused-display poll that tracking started, if one is running.
    func settlePoll() async {
        await model.trackingPollTask?.value
    }

    /// Waits for the focus request in flight, if any, and for the work queued behind it.
    func settleSwitch() async {
        await model.focusSwitchTask?.value
    }
}
