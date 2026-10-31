import AppKit
import Foundation
import Observation
import SwayModels
import Testing
import os

@testable import SwayUI

@MainActor
@Suite("AppModel Setup window")
struct AppModelSetupTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id

    // MARK: Where the window opens

    @Test func opensAtCameraAccessWhenTheCameraIsNotDecided() {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }

        h.openSetup()

        #expect(h.model.setupFlow?.step == .cameraAccess)
        #expect(h.pose.startCount == 0)
        #expect(!h.model.isCameraActive)
    }

    @Test func opensAtAccessibilityWhenOnlyAccessibilityIsMissing() {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }

        h.openSetup()

        #expect(h.model.setupFlow?.step == .accessibility)
        #expect(h.pose.startCount == 0)
    }

    @Test func aRecalibrationOpensAtTheCameraCheck() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.openSetup()

        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    @Test func aWindowNobodyAskedForDoesNotOpenAFlow() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.setupWindowDidAppear()

        #expect(h.model.setupFlow == nil)
        #expect(h.pose.startCount == 0, "The copy SwiftUI opens at launch never starts the camera")
    }

    @Test func closingTheWindowWhenItIsNotOpenDoesNothing() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.setupWindowDidDisappear()

        #expect(h.model.setupFlow == nil)
        #expect(h.model.cameraOperation == nil)
    }

    // MARK: Camera access

    @Test func continueShowsThePromptAndMovesOnWhenAccessIsGranted() async {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }
        h.openSetup()

        await h.model.requestCameraAccessFromSetup()

        #expect(h.camera.requestCount == 1)
        #expect(h.model.authorization == .authorized)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1)
    }

    @Test func grantingAccessHereAlsoAnswersTheMenusExplanationAndResumesTracking() async {
        let h = Harness.make(authorization: .notDetermined, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        #expect(h.model.permissionPrompt == .explanation)
        #expect(!h.model.trackingEnabled)
        h.openSetup()
        #expect(h.model.setupFlow?.step == .cameraAccess)

        await h.model.requestCameraAccessFromSetup()

        #expect(h.model.permissionPrompt == nil)
        #expect(h.model.pendingIntent == nil)
        #expect(h.model.trackingEnabled, "The switch the user flipped carries on")
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.menuBanner == nil || h.model.menuBanner == .needsAccessibility)
    }

    @Test func aDeniedPromptStaysOnTheStepAndAGrantInSystemSettingsMovesOn() async {
        let h = Harness.make(authorization: .notDetermined)
        defer { h.tearDown() }
        h.camera.setAuthorizationAfterRequest(.denied)
        h.openSetup()

        await h.model.requestCameraAccessFromSetup()

        #expect(h.model.authorization == .denied)
        #expect(h.model.setupFlow?.step == .cameraAccess)
        #expect(h.pose.startCount == 0)

        h.camera.setAuthorization(.authorized)
        h.model.setupTick()

        #expect(h.model.authorization == .authorized)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1)
    }

    @Test func theTickAndReturningToTheAppNoticeAGrantMadeElsewhere() {
        let h = Harness.make(authorization: .denied)
        defer { h.tearDown() }
        h.openSetup()
        #expect(h.model.setupFlow?.step == .cameraAccess)

        h.camera.setAuthorization(.authorized)
        h.notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    // MARK: Accessibility

    @Test func theAccessibilityStepAsksOnceThenPollsEverySecondUntilGranted() {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }
        h.openSetup()
        let reads = h.focus.isTrustedCalls

        h.model.grantAccessibility()
        #expect(h.focus.requestTrustCalls == 1)
        #expect(h.system.openedAccessibilitySettingsCount == 1)

        h.model.setupTick()
        h.model.setupTick()
        #expect(h.focus.isTrustedCalls == reads + 2)
        #expect(h.model.setupFlow?.step == .accessibility)

        h.focus.setTrusted(true)
        h.model.setupTick()
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.isAccessibilityTrusted)

        let after = h.focus.isTrustedCalls
        h.model.setupTick()
        #expect(h.focus.isTrustedCalls == after, "The poll runs only while a permission step shows")
    }

    @Test func skippingMovesOnAndIsNotAskedAgainThisRun() async {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }
        h.openSetup()

        h.model.skipSetupAccessibility()
        #expect(h.model.setupFlow?.step == .cameraCheck)
        await h.model.cameraOperation?.value
        h.model.setupWindowDidDisappear()

        h.openSetup()
        #expect(h.model.setupFlow?.step == .cameraCheck, "Skipped for this app run")
    }

    @Test func skippingAccessibilityLeavesTrackingNeedingIt() async {
        let h = Harness.make(trusted: false, calibrated: true)
        defer { h.tearDown() }
        h.openSetup()
        h.model.skipSetupAccessibility()
        await h.model.cameraOperation?.value

        h.model.setupWindowDidDisappear()
        await h.startTracking()

        #expect(h.model.trackingStatus == .needsAccessibility)
    }

    @Test func thePermissionTimerRunsOnlyOnAPermissionStepAndOnlyWhenTheEnvironmentHasOne() async {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }
        h.openSetup()
        #expect(h.model.setupTickTask == nil, "The test environment has no timer")

        h.focus.setTrusted(true)
        h.model.setupTick()
        await h.model.cameraOperation?.value
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupTickTask == nil)
    }

    // MARK: Camera check

    @Test func theCameraRunsForTheCameraCheckWithoutLandmarksAndTrackingStaysOff() async {
        let h = Harness.make()
        defer { h.tearDown() }

        h.openSetup()
        await h.model.cameraOperation?.value

        #expect(h.model.wantsCamera)
        #expect(h.model.isCameraActive)
        #expect(h.pose.configurations == [PoseSourceConfiguration(cameraDeviceID: nil, includeLandmarks: false)])
        #expect(!h.model.trackingEnabled)
        #expect(h.defaults.object(forKey: "sway.trackingEnabled") == nil)
    }

    @Test func closingTheWindowStopsTheCameraWhenTrackingIsOff() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive)

        h.model.setupWindowDidDisappear()
        await h.model.cameraOperation?.value

        #expect(h.model.setupFlow == nil)
        #expect(!h.model.isCameraActive)
        #expect(!h.model.wantsCamera)
        #expect(h.pose.stopCount >= 1)
    }

    @Test func closingTheWindowKeepsTheCameraWhenTrackingNeedsIt() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        h.openSetup()
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1, "The running stream is kept")

        h.model.setupWindowDidDisappear()
        await h.model.cameraOperation?.value

        #expect(h.model.isCameraActive)
        #expect(h.pose.startCount == 1)
        #expect(h.pose.stopCount == 0)
    }

    @Test func aCameraThatFailsToStartCanBeTriedAgainWithAnotherCamera() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.pose.setStartError(.noDevice)
        h.openSetup()
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)
        #expect(h.model.status == .failed(.noDevice))

        h.pose.setStartError(nil)
        await h.model.selectCamera(Fixtures.externalCamera.id)

        #expect(h.model.isCameraActive)
        #expect(h.pose.configurations.last?.cameraDeviceID == Fixtures.externalCamera.id)
    }

    @Test func tryAgainRestartsAFailedCamera() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.pose.setStartError(.noDevice)
        h.openSetup()
        await h.model.cameraOperation?.value
        h.pose.setStartError(nil)

        h.model.retrySetupCamera()
        await h.model.cameraOperation?.value

        #expect(h.model.isCameraActive)
    }

    @Test func theCameraCheckSaysItIsCalibratingInTheStatus() async {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.trackingStatus == .paused)

        await h.openSetupOnCameraCheck()
        #expect(h.model.trackingStatus == .calibrating)
        #expect(h.model.statusLine.hasPrefix("Calibrating"))

        h.model.setupWindowDidDisappear()
        await h.model.cameraOperation?.value
        #expect(h.model.trackingStatus == .paused)
    }

    @Test func thePermissionStepsDoNotShowCalibrating() {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }
        h.openSetup()
        #expect(h.model.trackingStatus == .paused)
    }

    // MARK: The hint

    @Test func theHintFollowsTheLatestPoseOnTheCameraCheck() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        #expect(h.model.framingAdvice == .noFace)

        h.feed()
        #expect(h.model.framingAdvice == .good)

        h.clock.advance(by: 0.5)
        h.feed(faceBounds: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))
        #expect(h.model.framingAdvice == .closer)

        h.clock.advance(by: 0.5)
        h.feed(face: false)
        #expect(h.model.framingAdvice == .noFace)
    }

    @Test func theHintRefreshesAtMostFiveTimesASecond() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        let good = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let small = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)

        var previous = h.model.framingAdvice
        var changes = 0
        for frame in 0..<45 {
            // 15 frames a second for 3 s, the face flipping between good and too small on every frame.
            h.clock.set(Double(frame) / 15)
            h.feed(faceBounds: frame.isMultiple(of: 2) ? good : small)
            if h.model.framingAdvice != previous {
                changes += 1
                previous = h.model.framingAdvice
            }
        }

        #expect(changes <= 16, "Five a second over three seconds, plus the first")
        #expect(changes >= 1)
    }

    @Test func aChangeInTheFaceShowsWithinAFifthOfASecond() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        let good = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let small = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        h.feed(faceBounds: good)
        #expect(h.model.framingAdvice == .good)

        // The face moves away at 1.0 s; the hint must show it by 1.0 s plus one refresh interval (and a frame).
        var shownAt: Double?
        for frame in 15...30 {
            let time = Double(frame) / 15
            h.clock.set(time)
            h.feed(faceBounds: time >= 1 ? small : good)
            if shownAt == nil, h.model.framingAdvice == .closer { shownAt = time }
        }

        let delay = (shownAt ?? .infinity) - 1
        #expect(delay <= AppModel.framingRefreshInterval + 1.0 / 15 + 1e-9)
    }

    @Test func aSteadyHintIsNeverReassigned() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        h.feed()
        let model = h.model

        let count = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = model.framingAdvice
        } onChange: {
            count.withLock { $0 += 1 }
        }
        for frame in 1...60 {
            h.clock.set(Double(frame) / 15)
            h.feed()
        }

        #expect(count.withLock { $0 } == 0, "The same advice on every refresh is not a change")
    }

    @Test func theHintIsNotComputedOutsideTheCameraCheck() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        h.feed()
        #expect(h.model.framingAdvice == .noFace, "No Setup window")

        await h.openSetupOnCameraCheck()
        h.clock.advance(by: 1)
        h.feed()
        #expect(h.model.framingAdvice == .good)

        await h.model.startCalibration()
        h.clock.advance(by: 1)
        h.feed(face: false)
        #expect(h.model.framingAdvice == .good, "The calibrating step does not refresh it")
    }

    @Test func theHintStartsOverWhenTheCameraCheckBeginsAgain() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        h.feed()
        #expect(h.model.framingAdvice == .good)
        await h.model.startCalibration()

        h.overlay.pressEscape()

        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.framingAdvice == .noFace)
        h.feed()
        #expect(h.model.framingAdvice == .good, "The first sample after the reset is shown at once")
    }

    // MARK: Start calibration needs two displays

    @Test func withOneDisplayCalibrationDoesNotStart() async {
        let h = Harness.make(layout: Fixtures.oneDisplay)
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        #expect(!h.model.canStartCalibration)

        await h.model.startCalibration()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupMessage == .error("Connect a second display to calibrate."))
        #expect(h.overlay.presented.isEmpty)
    }

    @Test func aDisplayWithoutAScreenStopsCalibrationBeforeItStarts() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.overlay.unavailable = [Fixtures.right.id]
        await h.openSetupOnCameraCheck()

        await h.model.startCalibration()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(
            h.model.setupMessage
                == .error("Gander could not find the screen for Right. Check the display connections."))
        #expect(h.model.gateMessage == nil)
    }

    @Test func startCalibrationOnlyWorksFromTheCameraCheck() async {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }
        h.openSetup()
        #expect(h.model.setupFlow?.step == .accessibility)

        await h.model.startCalibration()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .accessibility)
    }

    // MARK: A full calibration

    @Test func aFullCalibrationRunsTwoRoundsWithoutLandmarksAndSavesTheCalibration() async throws {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()

        await h.model.startCalibration()

        #expect(h.model.gateRunState == .running)
        #expect(h.model.gatePurpose == .calibration)
        #expect(h.model.setupFlow?.step == .calibrating)
        #expect(h.overlay.lastProgress?.display.id == left)
        #expect(h.overlay.lastProgress?.phase == .settle)
        #expect(h.overlay.lastProgress?.phaseDuration == 1.5)
        #expect(h.overlay.lastProgress?.stepCount == 4)

        h.runCalibration()
        await h.model.cameraOperation?.value

        // The overlays visited every display twice, settling 1.5 s and holding 2.5 s each time.
        let holds = h.overlay.presented.filter { $0.phase == .hold }
        #expect(Set(holds.map(\.phaseDuration)) == [2.5])
        #expect(Set(h.overlay.presented.map(\.rounds)) == [2])
        let visited = h.overlay.presented.map { "\($0.round):\($0.display.id.rawValue):\($0.phase)" }
        for expected in [
            "1:display-left:settle", "1:display-left:hold", "1:display-right:settle", "1:display-right:hold",
            "2:display-left:settle", "2:display-right:hold",
        ] {
            #expect(visited.contains(expected), "\(expected)")
        }
        #expect(!h.overlay.isShowing)

        // The camera never restarted with landmarks.
        #expect(h.pose.startCount == 1)
        #expect(h.pose.configurations.allSatisfy { !$0.includeLandmarks })

        // The trace: two rounds over both displays, 10 hold samples each (2.5 s at 4 samples a second).
        let fit = try #require(h.engine.fitCalls.first)
        #expect(h.engine.fitCalls.count == 1)
        #expect(fit.features == .visionAngles)
        #expect(fit.rounds == nil)
        #expect(fit.trace.segments.map(\.round) == [1, 1, 2, 2])
        #expect(fit.trace.segments.map(\.displayID) == [left, right, left, right])
        #expect(fit.trace.segments.allSatisfy { $0.samples.count == 10 })
        #expect(fit.trace.layout == Fixtures.twoDisplays)
        #expect(fit.trace.cameraName == Fixtures.builtInCamera.name)

        // Saved into the library, analyzed, and shown.
        #expect(h.storedLibrary()?.profiles == [Fixtures.profile()])
        #expect(h.model.activeCalibration?.saved == Fixtures.profile())
        #expect(h.analyzer.analyzedTraces == [fit.trace])
        #expect(h.analyzer.analyzedThresholds == [.default])
        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.setupResult?.quality == .good)
        #expect(h.model.setupResult?.text == "Calibration looks good.")
        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gatePurpose == .gateTest)
    }

    @Test func aCalibrationLeavesTheGateWindowAlone() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #expect(h.model.analysis == nil)
        #expect(h.model.analysisTrace == nil)
        #expect(!h.model.isShowingReport)
        #expect(h.model.lastFittedProfile == nil)
        #expect(h.model.calibrationMessage == nil)
        #expect(h.model.gateMessage == nil)
        #expect(h.model.traceSaveStatus == .none)
    }

    @Test func theCalibrationTraceIsSavedInDebugBuilds() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #if DEBUG
        #expect(h.store.saved.count == 1)
        #else
        #expect(h.store.saved.isEmpty)
        #endif
    }

    @Test func aFailedTraceSaveDoesNotStopTheResult() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.store.setSaveError(.io("disk full"))
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.setupResult?.isSaved == true)
        #expect(h.model.traceSaveStatus == .none)
    }

    @Test func theResultStepReleasesTheCameraWhenTrackingIsOff() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #expect(h.model.setupFlow?.step == .result)
        #expect(!h.model.wantsCamera)
        #expect(!h.model.isCameraActive)
        #expect(h.model.trackingStatus == .paused)
    }

    // MARK: Verdicts

    private func result(for analysis: GateAnalysis) async -> SetupResult? {
        let h = Harness.make(analysis: analysis)
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.completeCalibration()
        return h.model.setupResult
    }

    @Test func aGoVerdictSaysTheCalibrationLooksGood() async {
        let result = await result(for: Fixtures.analysis(visionVerdict: .go))
        #expect(result?.quality == .good)
        #expect(result?.text == "Calibration looks good.")
    }

    @Test func aMarginalVerdictNamesTheWeakestPair() async {
        let result = await result(for: Fixtures.analysis(visionVerdict: .marginal))
        #expect(result?.quality == .fair)
        #expect(
            result?.text
                == "Calibration saved. Left and Right are close together, so switching between them may be slower.")
    }

    @Test func aNoGoVerdictAsksToMoveTheCamera() async {
        let result = await result(for: Fixtures.analysis(visionVerdict: .noGo))
        #expect(result?.quality == .poor)
        #expect(
            result?.text
                == "Calibration saved, but Left and Right are hard to tell apart. "
                + "Try moving the camera, then calibrate again.")
    }

    @Test func insufficientDataSuggestsCalibratingAgain() async {
        let result = await result(for: Fixtures.analysis(visionVerdict: .insufficientData))
        #expect(result?.quality == .fair)
        #expect(
            result?.text
                == "Calibration saved, but Gander saw your face only briefly on some displays. "
                + "If switching feels unreliable, calibrate again.")
    }

    @Test func aFitThatLeftOutADisplaySavesNothingAndNamesIt() async {
        // Three displays, but the fitter kept only two: the face was seen too rarely on the third.
        let h = Harness.make(layout: Fixtures.threeDisplays)
        defer { h.tearDown() }
        h.engine.setFitResult(.success(Fixtures.profile(layout: Fixtures.twoDisplays)))
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        let far = DisplayLabeler.labels(for: Fixtures.threeDisplays)[Fixtures.far.id] ?? ""
        #expect(h.model.setupResult?.isSaved == false)
        #expect(
            h.model.setupResult?.text
                == "Gander couldn't see your face well enough while you looked at \(far). "
                + "Make sure the camera sees you from every display, then calibrate again.")
        #expect(h.model.library.profiles.isEmpty)
        #expect(h.model.activeCalibration == nil)
    }

    @Test func missingDisplaysAreListedInPlainEnglish() {
        #expect(SetupResult.listed(["A"]) == "A")
        #expect(SetupResult.listed(["A", "B"]) == "A and B")
        #expect(SetupResult.listed(["A", "B", "C"]) == "A, B, and C")
    }

    @Test func theVisionAnglesVerdictDecidesNotTheOverallOne() async {
        // The helper's overall verdict and best feature set say GO; only the Vision report says NO-GO.
        let analysis = Fixtures.analysis(visionVerdict: .noGo)
        #expect(analysis.overall == .go)
        let result = await result(for: analysis)
        #expect(result?.quality == .poor)
    }

    // MARK: A fit that fails

    @Test func aFailedFitSavesNothingAndSaysWhy() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.setupResult == .failed(CalibrationError.tooFewDisplays.userMessage))
        #expect(h.model.setupResult?.isSaved == false)
        #expect(
            h.model.setupResult?.text
                == "Not enough face samples on at least two displays to calibrate. "
                + "Keep your face in view of the camera and try again.")
        #expect(h.model.library.profiles.isEmpty)
        #expect(h.storedLibrary() == nil)
        #expect(h.model.activeCalibration == nil)
        #expect(h.analyzer.analyzedTraces.isEmpty, "Nothing to rate")
        #expect(h.model.calibrationMessage == nil, "The gate window's message is not used")
    }

    @Test func aFailedFitKeepsAnEarlierCalibration() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.featuresMissing(.visionAngles)))
        await h.openSetupOnCameraCheck()

        await h.completeCalibration()

        #expect(h.model.setupResult?.isSaved == false)
        #expect(h.model.library.profiles == [Fixtures.profile()])
        #expect(h.model.activeCalibration != nil)
    }

    @Test func calibrateAgainAfterAFailedFitReturnsToTheCameraCheckAndCanSucceed() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))
        await h.openSetupOnCameraCheck()
        await h.completeCalibration()
        #expect(h.model.setupResult?.isSaved == false)

        h.engine.setFitResult(.success(Fixtures.profile()))
        h.model.calibrateAgain()
        await h.model.cameraOperation?.value
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupResult == nil)
        h.reportRunning()
        await h.completeCalibration()

        #expect(h.model.setupResult?.quality == .good)
        #expect(h.model.library.profiles.count == 1)
    }

    // MARK: Cancelling

    @Test func escapeCancelsBackToTheCameraCheckWithAMessage() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()
        h.clock.advance(by: 0.5)
        h.feed()

        h.overlay.pressEscape()
        await h.model.cameraOperation?.value

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupMessage == .info("Calibration cancelled."))
        #expect(h.model.gateMessage == nil)
        #expect(!h.overlay.isShowing)
        #expect(h.model.isCameraActive, "The camera check keeps the camera")
        #expect(h.engine.fitCalls.isEmpty)
        #expect(h.model.library.profiles.isEmpty)
    }

    @Test func theCancelButtonDoesTheSame() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()

        h.model.cancelCalibration()

        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupMessage == .info("Calibration cancelled."))
        #expect(h.engine.fitCalls.isEmpty)
    }

    @Test func aCancelledCalibrationCanBeStartedAgainAndCompletes() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()
        h.overlay.pressEscape()

        await h.completeCalibration()

        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.setupMessage == nil, "A new run clears the old message")
        #expect(h.engine.fitCalls.count == 1)
    }

    @Test func closingTheWindowMidCalibrationCancelsItAndStopsTheCamera() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()
        #expect(h.overlay.isShowing)

        h.model.setupWindowDidDisappear()
        await h.model.cameraOperation?.value

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow == nil)
        #expect(!h.overlay.isShowing)
        #expect(!h.model.isCameraActive)
        #expect(h.engine.fitCalls.isEmpty)
        #expect(h.model.trackingStatus == .paused)
    }

    @Test func aLayoutChangeCancelsTheCalibration() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()

        h.model.layoutDidChange(Fixtures.threeDisplays)

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(
            h.model.setupMessage == .info("The display arrangement changed, so the calibration was cancelled."))
        #expect(h.model.gateMessage == nil)
        #expect(!h.overlay.isShowing)
    }

    @Test func losingTheCameraAbortsTheCalibrationWithAnError() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()

        h.model.handle(.status(.interrupted("Camera disconnected")))

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupMessage?.kind == .error)
        #expect(h.model.setupMessage?.text.hasSuffix("Calibrate again.") == true)
        #expect(h.model.gateMessage == nil)
    }

    @Test func aStreamThatEndsAbortsTheCalibration() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status.isRunning }
        await h.model.startCalibration()
        #expect(h.model.gateRunState == .running)

        h.pose.finishStream()
        let ended = await waitUntil { h.model.gateRunState == .idle }

        #expect(ended)
        #expect(h.model.setupMessage == .error("The camera stopped unexpectedly. Calibrate again."))
        #expect(h.model.setupFlow?.step == .cameraCheck)
    }

    @Test func aCameraThatNeverStartsAbortsTheCalibration() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        // The camera check's camera never reports running.
        await h.model.startCalibration()
        #expect(h.model.gateRunState == .startingCamera)

        h.clock.advance(by: 11)
        h.model.gateTick()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupMessage?.kind == .error)
    }

    @Test func swayLosingTheForegroundCancelsTheCalibration() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()

        h.notifications.post(name: NSApplication.didResignActiveNotification, object: nil)

        #expect(h.model.gateRunState == .idle)
        #expect(
            h.model.setupMessage
                == .info("The calibration was cancelled because Gander was no longer the active app."))
    }

    @Test func theGateWindowClosingDoesNotCancelACalibration() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.model.startCalibration()

        h.model.cancelGateTest(reason: nil)

        #expect(h.model.gateRunState == .running)
        #expect(h.model.gatePurpose == .calibration)
        #expect(h.overlay.isShowing)
    }

    @Test func cancelCalibrationDoesNothingDuringAGateTest() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.model.startGateTest()
        h.reportRunning()
        #expect(h.model.gatePurpose == .gateTest)

        h.model.cancelCalibration()

        #expect(h.model.gateRunState == .running)
    }

    @Test func escapeDuringAGateTestKeepsTheGateTestWording() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.model.startGateTest()
        h.reportRunning()

        h.overlay.pressEscape()

        #expect(h.model.gateRunState == .idle)
        #expect(h.model.gateMessage == .info("Gate test cancelled."))
        #expect(h.model.setupMessage == nil)
    }

    // MARK: Start tracking and calibrate again

    @Test func startTrackingIsAUserActionThatIsSavedAndClosesTheFlow() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status.isRunning }
        await h.completeCalibration()
        #expect(h.model.setupFlow?.step == .result)
        #expect(h.defaults.object(forKey: "sway.trackingEnabled") == nil)

        await h.model.startTrackingFromSetup()

        #expect(h.model.trackingEnabled)
        #expect(h.defaults.bool(forKey: "sway.trackingEnabled"))
        #expect(h.model.setupFlow == nil)
        #expect(h.model.isCameraActive)
        #expect(h.relaunchedModel().trackingEnabled)
    }

    @Test func calibrateAgainReturnsToTheCameraCheckAndRestartsTheCamera() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.openSetupOnCameraCheck()
        await h.completeCalibration()
        #expect(!h.model.isCameraActive)

        h.model.calibrateAgain()
        await h.model.cameraOperation?.value

        #expect(h.model.setupFlow?.step == .cameraCheck)
        #expect(h.model.setupResult == nil)
        #expect(h.model.isCameraActive)
        #expect(h.pose.startCount == 2)
    }

    // MARK: Tracking holds

    /// A calibrated model with Tracking on, whose decider asks to switch to Right on every sample.
    private func switchingHarness() async -> Harness {
        let h = Harness.make(calibrated: true)
        await h.startTracking()
        await h.settlePoll()
        h.engine.script.set { sample, _ in
            Fixtures.decision(
                switchTo: Fixtures.right.id, phase: .coolingDown(until: sample.timestamp + 1),
                classification: Fixtures.classification(best: Fixtures.right.id))
        }
        h.focus.setResult(
            .focused(Fixtures.window(1, on: Fixtures.right), method: .appActivation, milliseconds: 100))
        return h
    }

    @Test func trackingHoldsOnTheCameraCheckAndTheCalibrationButNotOnAResultLeftBehind() async {
        let h = await switchingHarness()
        defer { h.tearDown() }
        #expect(h.model.isTrackingActive)

        h.openSetup()
        await h.model.cameraOperation?.value
        #expect(!h.model.isTrackingActive)
        h.clock.advance(by: 1)
        h.feed()
        await h.settleSwitch()
        #expect(h.focus.focusCalls.isEmpty, "The camera check holds")

        await h.model.startCalibration()
        #expect(!h.model.isTrackingActive)
        h.runCalibration()
        await h.model.cameraOperation?.value
        #expect(h.model.setupFlow?.step == .result)
        #expect(h.model.isTrackingActive, "The result step doesn't hold by itself")
        h.appState.isActive = true
        h.notifications.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        h.clock.advance(by: 1)
        h.feed()
        await h.settleSwitch()
        #expect(h.focus.focusCalls.isEmpty, "Held while the window is in front")

        h.appState.isActive = false
        h.notifications.post(name: NSWindow.didResignKeyNotification, object: nil)
        h.clock.advance(by: 1)
        h.feed()
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "A result left behind other apps doesn't stop switching")
    }

    @Test func trackingResumesWhenTheWindowCloses() async {
        let h = await switchingHarness()
        defer { h.tearDown() }
        h.openSetup()
        await h.model.cameraOperation?.value
        h.clock.advance(by: 1)
        h.feed()
        #expect(h.focus.focusCalls.isEmpty)

        h.model.setupWindowDidDisappear()
        #expect(h.model.isTrackingActive)
        h.clock.advance(by: 1)
        h.feed()
        await h.settleSwitch()

        #expect(h.focus.focusCalls == [right])
    }

    @Test func thePermissionStepsDoNotHoldTracking() async {
        let h = await switchingHarness()
        defer { h.tearDown() }
        h.focus.setTrusted(true)
        // Accessibility granted at the time, then revoked: the window opens on the Accessibility step.
        h.model.isAccessibilityTrusted = true
        h.focus.setTrusted(false)

        h.openSetup()

        #expect(h.model.setupFlow?.step == .accessibility)
        #expect(!h.model.isSetupHoldingTracking)
    }

    @Test func openingTheWindowResetsTheDeciderAndTheLoop() async {
        let h = await switchingHarness()
        defer { h.tearDown() }
        let resets = h.engine.lastRecorder?.resetCount ?? 0

        h.openSetup()

        #expect((h.engine.lastRecorder?.resetCount ?? 0) > resets)
        #expect(h.model.lookSummary == .off)
    }

    @Test func theFocusedDisplayPollStopsWhileTheWindowHoldsTracking() async {
        let h = await switchingHarness()
        defer { h.tearDown() }
        #expect(h.model.isPollingFocus)

        h.openSetup()
        #expect(!h.model.isPollingFocus)

        h.model.setupWindowDidDisappear()
        #expect(h.model.isPollingFocus)
    }

    // MARK: Per camera

    @Test func theCalibrationIsSavedForTheCameraThatRanIt() async {
        let h = Harness.make(autoRun: true, savedCameraID: Fixtures.externalCamera.id)
        defer { h.tearDown() }
        h.engine.setFitResult(
            .success(Fixtures.profile(cameraName: Fixtures.externalCamera.name)))
        h.openSetup()
        await h.model.cameraOperation?.value
        _ = await waitUntil { h.model.status.isRunning }

        await h.completeCalibration()

        let fit = h.engine.fitCalls.first
        #expect(fit?.trace.cameraName == Fixtures.externalCamera.name)
        #expect(h.model.activeCalibration?.saved.cameraName == Fixtures.externalCamera.name)
    }
}
