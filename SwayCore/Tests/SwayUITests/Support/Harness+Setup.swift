import CoreGraphics
import Foundation
import SwayModels

@testable import SwayUI

extension Harness {
    /// Opens the Set Up Sway window as the menu would: the request first, then the window appearing. With an empty
    /// library the window opens on the welcome step; unless `welcome` is set, **Get Started** is pressed, so the
    /// tests of the steps after it see the first step that applies.
    func openSetup(welcome: Bool = false) {
        model.noteWindowRequested(SwayWindowID.setup)
        model.setupWindowDidAppear()
        if !welcome { model.getStartedFromSetup() }
    }

    /// Opens the window on the camera check and reports the camera running.
    func openSetupOnCameraCheck() async {
        openSetup()
        await model.cameraOperation?.value
        reportRunning()
    }

    /// Opens the Sway Settings window as the menu would.
    func openSettings() {
        model.noteWindowRequested(SwayWindowID.settings)
        model.settingsWindowDidAppear()
    }

    /// Feeds a sample every 0.25 s, aimed at whichever display the overlay shows, until the run ends.
    func runCalibration() {
        var frames = 0
        while model.gateRunState == .running, frames < 2000 {
            clock.advance(by: 0.25)
            let target = overlay.lastProgress?.display.id
            feed(yaw: target == Fixtures.left.id ? -20 : 20)
            model.gateTick()
            frames += 1
        }
    }

    /// Starts the calibration from the camera check and runs it to the end.
    func completeCalibration() async {
        await model.startCalibration()
        runCalibration()
        await model.cameraOperation?.value
    }

    /// Offers a sample with a face box, stamped with the clock's current time.
    func feed(faceBounds bounds: CGRect) {
        model.handle(.sample(PoseSample(timestamp: clock.now, pose: Fixtures.pose(faceBounds: bounds))))
    }
}

extension Fixtures {
    /// A pose whose face box is `bounds`.
    static func pose(faceBounds bounds: CGRect) -> HeadPose {
        var result = Fixtures.pose()
        result.faceBounds = bounds
        return result
    }

    /// An analysis whose Vision-angles report has `verdict` (with Left and Right as the weakest pair), while the
    /// overall verdict and the best feature set say GO, so a test can tell which one is read.
    static func analysis(visionVerdict verdict: GateVerdict, pairs: [PairSeparation]? = nil) -> GateAnalysis {
        var vision = report(.visionAngles, verdict: verdict)
        if let pairs { vision.pairs = pairs }
        return GateAnalysis(
            reports: [vision, report(.landmarkAngles, verdict: .go)], overall: .go, bestFeatureSet: .landmarkAngles,
            thresholds: .default)
    }
}
