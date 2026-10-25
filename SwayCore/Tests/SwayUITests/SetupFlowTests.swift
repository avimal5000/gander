import Testing

@testable import SwayUI

@Suite("Setup flow")
struct SetupFlowTests {
    private func facts(camera: Bool = true, trusted: Bool = true, skipped: Bool = false) -> SetupFlow.Facts {
        SetupFlow.Facts(cameraAuthorized: camera, accessibilityTrusted: trusted, accessibilitySkipped: skipped)
    }

    // MARK: Where it opens

    @Test func opensAtCameraAccessUnlessTheCameraIsAuthorized() {
        #expect(SetupFlow(facts: facts(camera: false)).step == .cameraAccess)
        #expect(SetupFlow(facts: facts(camera: false, trusted: false)).step == .cameraAccess)
        #expect(SetupFlow(facts: facts(camera: false, trusted: true, skipped: true)).step == .cameraAccess)
    }

    @Test func opensAtAccessibilityWhenTheCameraIsAuthorizedButAccessibilityIsNot() {
        #expect(SetupFlow(facts: facts(trusted: false)).step == .accessibility)
    }

    @Test func aSkippedAccessibilityStepIsNotAskedAgain() {
        #expect(SetupFlow(facts: facts(trusted: false, skipped: true)).step == .cameraCheck)
    }

    @Test func aRecalibrationOpensAtTheCameraCheck() {
        #expect(SetupFlow(facts: facts()).step == .cameraCheck)
    }

    // MARK: Permissions moving it on

    @Test func grantingTheCameraMovesOnToTheNextStepThatApplies() {
        var flow = SetupFlow(facts: facts(camera: false, trusted: false))
        flow.update(facts(camera: false, trusted: false))
        #expect(flow.step == .cameraAccess, "Nothing changed")

        flow.update(facts(camera: true, trusted: false))
        #expect(flow.step == .accessibility)

        var trusted = SetupFlow(facts: facts(camera: false))
        trusted.update(facts(camera: true))
        #expect(trusted.step == .cameraCheck, "Accessibility was already granted")

        var skipped = SetupFlow(facts: facts(camera: false, trusted: false, skipped: true))
        skipped.update(facts(camera: true, trusted: false, skipped: true))
        #expect(skipped.step == .cameraCheck)
    }

    @Test func grantingOrSkippingAccessibilityMovesOn() {
        var granted = SetupFlow(facts: facts(trusted: false))
        granted.update(facts(trusted: false))
        #expect(granted.step == .accessibility)
        granted.update(facts(trusted: true))
        #expect(granted.step == .cameraCheck)

        var skipped = SetupFlow(facts: facts(trusted: false))
        skipped.update(facts(trusted: false, skipped: true))
        #expect(skipped.step == .cameraCheck)
    }

    @Test func aRevokedCameraSendsTheEarlyStepsBackToCameraAccess() {
        var onAccessibility = SetupFlow(facts: facts(trusted: false))
        onAccessibility.update(facts(camera: false, trusted: false))
        #expect(onAccessibility.step == .cameraAccess)

        var onCheck = SetupFlow(facts: facts())
        onCheck.update(facts(camera: false))
        #expect(onCheck.step == .cameraAccess)
    }

    @Test func aRevokedAccessibilityDoesNotSendTheCameraCheckBack() {
        var flow = SetupFlow(facts: facts())
        flow.update(facts(trusted: false))
        #expect(flow.step == .cameraCheck)
    }

    @Test func theCalibrationAndTheResultIgnoreChangedPermissions() {
        var flow = SetupFlow(facts: facts())
        flow.startCalibration()
        flow.update(facts(camera: false, trusted: false))
        #expect(flow.step == .calibrating)
        flow.calibrationFinished()
        flow.update(facts(camera: false, trusted: false))
        #expect(flow.step == .result)
    }

    // MARK: The calibration

    @Test func startingCalibratingFinishingAndCalibratingAgain() {
        var flow = SetupFlow(facts: facts())
        flow.startCalibration()
        #expect(flow.step == .calibrating)
        flow.calibrationFinished()
        #expect(flow.step == .result)
        flow.calibrateAgain()
        #expect(flow.step == .cameraCheck)
    }

    @Test func cancellingReturnsToTheCameraCheck() {
        var flow = SetupFlow(facts: facts())
        flow.startCalibration()
        flow.calibrationCancelled()
        #expect(flow.step == .cameraCheck)
    }

    @Test func aFailedFitStillShowsTheResultStepAndCalibratingAgainWorks() {
        // The step is the same for a good and a failed fit; the model keeps what the result says.
        var flow = SetupFlow(facts: facts())
        flow.startCalibration()
        flow.calibrationFinished()
        #expect(flow.step == .result)
        flow.calibrateAgain()
        flow.startCalibration()
        #expect(flow.step == .calibrating)
    }

    @Test func movesOutOfTurnDoNothing() {
        var onCheck = SetupFlow(facts: facts())
        onCheck.calibrationFinished()
        onCheck.calibrationCancelled()
        onCheck.calibrateAgain()
        #expect(onCheck.step == .cameraCheck)

        var onPermission = SetupFlow(facts: facts(trusted: false))
        onPermission.startCalibration()
        #expect(onPermission.step == .accessibility)

        var calibrating = SetupFlow(facts: facts())
        calibrating.startCalibration()
        calibrating.startCalibration()
        calibrating.calibrateAgain()
        #expect(calibrating.step == .calibrating)

        var onResult = SetupFlow(facts: facts())
        onResult.startCalibration()
        onResult.calibrationFinished()
        onResult.calibrationCancelled()
        onResult.startCalibration()
        #expect(onResult.step == .result)
    }

    // MARK: What each step asks of the app

    @Test func theCameraRunsOnlyForTheCameraCheckAndTheCalibration() {
        let needing: [SetupFlow.Step] = [.cameraCheck, .calibrating]
        for step in SetupFlow.Step.allSteps {
            #expect(flow(at: step).needsCamera == needing.contains(step), "\(step)")
        }
    }

    @Test func trackingHoldsOnTheCameraCheckTheCalibrationAndTheResult() {
        let holding: [SetupFlow.Step] = [.cameraCheck, .calibrating]
        for step in SetupFlow.Step.allSteps {
            #expect(flow(at: step).holdsTracking == holding.contains(step), "\(step)")
        }
    }

    @Test func onlyTheTwoPermissionStepsWaitForAPermission() {
        for step in SetupFlow.Step.allSteps {
            #expect(flow(at: step).isPermissionStep == (step == .cameraAccess || step == .accessibility), "\(step)")
        }
    }

    @Test func stepsAreNumberedOneToFiveAndTheWelcomeIsNotCounted() {
        #expect(SetupFlow.stepCount == 5)
        #expect(flow(at: .cameraAccess).step.rawValue == 1)
        #expect(flow(at: .result).step.rawValue == 5)
        #expect(flow(at: .welcome).step.rawValue == 0, "Not one of the five numbered steps")
        #expect(SetupFlow.Step.allSteps.filter { $0.rawValue >= 1 }.count == SetupFlow.stepCount)
    }

    // MARK: The welcome step

    @Test func theWelcomeOpensFirstOnlyWhenAskedFor() {
        #expect(SetupFlow(facts: facts(), showsWelcome: true).step == .welcome)
        #expect(SetupFlow(facts: facts(camera: false), showsWelcome: true).step == .welcome)
        #expect(SetupFlow(facts: facts(), showsWelcome: false).step == .cameraCheck)
        #expect(SetupFlow(facts: facts()).step == .cameraCheck, "A recalibration has no welcome")
    }

    @Test func getStartedMovesToTheFirstStepThatApplies() {
        var needsCamera = SetupFlow(facts: facts(camera: false, trusted: false), showsWelcome: true)
        needsCamera.getStarted(facts(camera: false, trusted: false))
        #expect(needsCamera.step == .cameraAccess)

        var needsAccessibility = SetupFlow(facts: facts(trusted: false), showsWelcome: true)
        needsAccessibility.getStarted(facts(trusted: false))
        #expect(needsAccessibility.step == .accessibility)

        var skipped = SetupFlow(facts: facts(trusted: false, skipped: true), showsWelcome: true)
        skipped.getStarted(facts(trusted: false, skipped: true))
        #expect(skipped.step == .cameraCheck)

        var allGranted = SetupFlow(facts: facts(), showsWelcome: true)
        allGranted.getStarted(facts())
        #expect(allGranted.step == .cameraCheck)
    }

    @Test func getStartedUsesTheFactsOfThatMomentNotOfTheOpening() {
        var flow = SetupFlow(facts: facts(camera: false), showsWelcome: true)
        flow.getStarted(facts(camera: true))
        #expect(flow.step == .cameraCheck, "The camera was allowed while the welcome was open")
    }

    @Test func theWelcomeStaysUntilGetStartedWhateverThePermissionsDo() {
        var flow = SetupFlow(facts: facts(camera: false), showsWelcome: true)
        flow.update(facts(camera: true))
        flow.update(facts(camera: false, trusted: false))
        #expect(flow.step == .welcome)
    }

    @Test func theWelcomeAsksNothingOfTheApp() {
        let welcome = flow(at: .welcome)
        #expect(!welcome.needsCamera)
        #expect(!welcome.holdsTracking)
        #expect(!welcome.isPermissionStep)
    }

    @Test func movesThatBelongToOtherStepsDoNothingOnTheWelcome() {
        var flow = SetupFlow(facts: facts(), showsWelcome: true)
        flow.startCalibration()
        flow.calibrationFinished()
        flow.calibrationCancelled()
        flow.calibrateAgain()
        #expect(flow.step == .welcome)
    }

    @Test func getStartedDoesNothingOnAnyOtherStep() {
        for step in SetupFlow.Step.allSteps where step != .welcome {
            var flow = flow(at: step)
            flow.getStarted(facts(camera: false))
            #expect(flow.step == step, "\(step)")
        }
    }

    private func flow(at step: SetupFlow.Step) -> SetupFlow {
        var flow: SetupFlow
        switch step {
        case .welcome: flow = SetupFlow(facts: facts(), showsWelcome: true)
        case .cameraAccess: flow = SetupFlow(facts: facts(camera: false))
        case .accessibility: flow = SetupFlow(facts: facts(trusted: false))
        case .cameraCheck: flow = SetupFlow(facts: facts())
        case .calibrating:
            flow = SetupFlow(facts: facts())
            flow.startCalibration()
        case .result:
            flow = SetupFlow(facts: facts())
            flow.startCalibration()
            flow.calibrationFinished()
        }
        return flow
    }
}

extension SetupFlow.Step {
    /// Every step, the welcome first.
    static let allSteps: [SetupFlow.Step] = [
        .welcome, .cameraAccess, .accessibility, .cameraCheck, .calibrating, .result,
    ]
}
