import Foundation
import SwayModels
import SwiftUI
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel Setup welcome step")
struct AppModelWelcomeTests {
    // MARK: When it shows

    @Test func firstSetupOpensOnTheWelcomeAndAsksForNothingYet() {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }
        #expect(h.model.library.profiles.isEmpty)

        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .welcome)
        #expect(h.camera.requestCount == 0, "No permission prompt before Get Started")
        #expect(h.pose.startCount == 0)
        #expect(!h.model.isCameraActive)
        #expect(!h.model.isSetupUsingCamera)
        #expect(!h.model.isSetupHoldingTracking)
    }

    @Test func aRecalibrationSkipsTheWelcome() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    @Test func aNewDisplaySetupWithOtherCalibrationsSkipsTheWelcomeToo() {
        let h = Harness.make(
            layout: Fixtures.threeDisplays, seed: { Harness.seedLibrary([Fixtures.profile()], into: $0) })
        defer { h.tearDown() }
        #expect(h.model.activeCalibration == nil)

        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    @Test func deletingEveryCalibrationBringsTheWelcomeBack() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        h.model.setupWindowDidDisappear()

        h.model.deleteCalibration(Fixtures.profile().key)
        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .welcome)
    }

    @Test func theWelcomeComesBackWhenTheWindowIsOpenedAgainBeforeCalibrating() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        h.model.getStartedFromSetup()
        h.model.setupWindowDidDisappear()

        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .welcome, "Still nothing calibrated")
    }

    // MARK: Get Started

    @Test func getStartedGoesToTheFirstStepThatApplies() {
        let denied = Harness.make(authorization: .notDetermined)
        defer { denied.tearDown() }
        denied.openSetup(welcome: true)
        denied.model.getStartedFromSetup()
        #expect(denied.model.setupFlow?.step == .cameraAccess)

        let untrusted = Harness.make(trusted: false)
        defer { untrusted.tearDown() }
        untrusted.openSetup(welcome: true)
        untrusted.model.getStartedFromSetup()
        #expect(untrusted.model.setupFlow?.step == .accessibility)
    }

    @Test func getStartedOntoTheCameraCheckStartsTheCamera() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(h.pose.startCount == 0)

        h.model.getStartedFromSetup()
        await h.model.cameraOperation?.value

        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.pose.startCount == 1)
        #expect(h.model.isSetupHoldingTracking, "The camera check holds switching, as before")
    }

    @Test func getStartedReadsThePermissionsAgain() {
        let h = Harness.make(authorization: .notDetermined, trusted: false)
        defer { h.tearDown() }
        h.openSetup(welcome: true)

        // The user read the welcome for a while and allowed both in System Settings meanwhile.
        h.camera.setAuthorization(.authorized)
        h.focus.setTrusted(true)
        h.model.getStartedFromSetup()

        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    @Test func getStartedDoesNothingOutsideTheWelcome() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(h.model.setupFlow?.step == .cameraCheck)

        h.model.getStartedFromSetup()
        #expect(h.model.setupFlow?.step == .cameraCheck)

        let closed = Harness.make()
        defer { closed.tearDown() }
        closed.model.getStartedFromSetup()
        #expect(closed.model.setupFlow == nil)
    }

    @Test func thePermissionTimerAndTheCameraStayOffOnTheWelcome() {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }
        h.openSetup(welcome: true)

        h.camera.setAuthorization(.authorized)
        h.model.setupTick()

        #expect(h.model.setupFlow?.step == .welcome, "Only Get Started leaves the welcome")
        #expect(h.pose.startCount == 0)
    }

    @Test func theRestOfSetupWorksAfterTheWelcome() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        h.model.getStartedFromSetup()
        await h.model.cameraOperation?.value
        h.reportRunning()

        await h.completeCalibration()

        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.setupResult?.isSaved == true)
        #expect(h.model.library.profiles.count == 1)
    }

    // MARK: Words

    @Test func theWelcomeSaysExactlyWhatTheSpecSays() {
        #expect(SetupPresentation.welcomeTitle == "Welcome to Sway")
        #expect(
            SetupPresentation.welcomeLine
                == "Look at a display, and Sway moves your typing there. The pointer never moves.")
        #expect(
            SetupPresentation.welcomePrivacy
                == "Your camera stays private. Sway reads only which way your head is turned, on this Mac. Video is never recorded, saved, or sent anywhere."
        )
        #expect(SetupPresentation.welcomeButton == "Get Started")
        #expect(SetupView.title(for: .welcome) == "Welcome to Sway")
    }

    @Test func everyNumberedStepKeepsItsTitle() {
        #expect(SetupView.title(for: .cameraAccess) == "Camera access")
        #expect(SetupView.title(for: .accessibility) == "Accessibility access")
        #expect(SetupView.title(for: .cameraCheck) == "Check your camera")
        #expect(SetupView.title(for: .calibrating) == "Look at each display")
        #expect(SetupView.title(for: .result) == "Calibration result")
    }

    @Test func theMotionIsTwoTenthsOfASecondUnlessReduced() {
        let fade: Animation? = .easeInOut(duration: 0.2)
        #expect(SetupView.stepAnimation(reduceMotion: true) == nil)
        #expect(SetupView.stepAnimation(reduceMotion: false) == fade)
        #expect(MenuContentView.bannerAnimation(reduceMotion: true) == nil)
        #expect(MenuContentView.bannerAnimation(reduceMotion: false) == fade)
    }
}
