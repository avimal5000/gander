import AppKit
import Foundation
import SwayModels
import Testing

@testable import SwayUI

@Suite("Status presentation")
struct StatusPresentationTests {
    @Test func captureStatusSummariesNameTheState() {
        #expect(CaptureStatus.stopped.summary == "Camera off")
        #expect(CaptureStatus.starting.summary == "Starting camera\u{2026}")
        #expect(CaptureStatus.running(nil).summary == "Running")
        #expect(CaptureStatus.suspended(.screenLocked).summary == "Suspended: screen locked")
        #expect(CaptureStatus.suspended(.systemSleep).summary == "Suspended: system asleep")
        #expect(CaptureStatus.suspended(.displaysAsleep).summary == "Suspended: displays asleep")
        #expect(CaptureStatus.interrupted("Camera disconnected").summary == "Interrupted: Camera disconnected")
        #expect(CaptureStatus.failed(.runtimeFailure("boom")).summary == "Failed: boom")
    }

    @Test func traceErrorsExplainThemselves() {
        #expect(TraceStoreError.disabledInReleaseBuilds.userMessage == "Traces are only saved in debug builds.")
        #expect(TraceStoreError.io("disk full").userMessage.contains("disk full"))
        #expect(TraceStoreError.decoding("bad key").userMessage.contains("bad key"))
        #expect(userMessage(for: TraceStoreError.io("x")).contains("x"))
        #expect(userMessage(for: CameraError.noDevice) == CameraError.noDevice.userMessage)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func anglesAreSignedWithOneDecimal() {
        #expect(Formatting.degrees(12.34) == "+12.3\u{00B0}")
        #expect(Formatting.degrees(-0.04) == "-0.0\u{00B0}")
        #expect(Formatting.degrees(nil) == Formatting.missing)
    }

    @Test func percentagesAndRates() {
        #expect(Formatting.percent(0.9731) == "97.3%")
        #expect(Formatting.percent(nil) == Formatting.missing)
        #expect(Formatting.wholePercent(0.9) == "90%")
        #expect(Formatting.fps(14.96) == "15.0 fps")
        #expect(Formatting.oneDecimal(3.14159) == "3.1")
        #expect(Formatting.seconds(26) == "26 s")
    }

    @Test func verdictTitlesMatchTheSpecWording() {
        #expect(GateVerdict.go.title == "GO")
        #expect(GateVerdict.marginal.title == "MARGINAL")
        #expect(GateVerdict.noGo.title == "NO-GO")
        #expect(GateVerdict.insufficientData.title == "INSUFFICIENT DATA")
    }

    @Test func featureSetsProjectPosesOrReturnNil() throws {
        let full = Fixtures.pose(yaw: 5, pitch: 6, landmarkYaw: 7, landmarkPitch: 8)
        let visionOnly = Fixtures.pose(yaw: 5, pitch: 6)
        let vision = try #require(PoseFeatureSet.visionAngles.point(of: full))
        let landmark = try #require(PoseFeatureSet.landmarkAngles.point(of: full))
        #expect(vision.x == 5 && vision.y == 6)
        #expect(landmark.x == 7 && landmark.y == 8)
        #expect(PoseFeatureSet.landmarkAngles.point(of: visionOnly) == nil)
    }
}

@Suite("Display helpers")
struct DisplayHelperTests {
    @Test func uniqueNamesStayAsTheyAre() {
        let labels = DisplayLabeler.labels(for: Fixtures.twoDisplays)
        #expect(labels[Fixtures.left.id] == "Left")
        #expect(labels[Fixtures.right.id] == "Right")
    }

    @Test func duplicateNamesGetANumberedSuffixInOrder() {
        let labels = DisplayLabeler.labels(for: [
            (id: DisplayID("a"), name: "Studio Display"),
            (id: DisplayID("b"), name: "Studio Display"),
            (id: DisplayID("c"), name: "Built-in"),
        ])
        #expect(labels[DisplayID("a")] == "Studio Display (1)")
        #expect(labels[DisplayID("b")] == "Studio Display (2)")
        #expect(labels[DisplayID("c")] == "Built-in")
    }

    @Test func screenMatchingUsesTheScreenNumberKey() {
        let description: [NSDeviceDescriptionKey: Any] = [ScreenMatcher.screenNumberKey: NSNumber(value: UInt32(11))]
        #expect(ScreenMatcher.matches(deviceDescription: description, cgDisplayID: 11))
        #expect(!ScreenMatcher.matches(deviceDescription: description, cgDisplayID: 12))
        #expect(!ScreenMatcher.matches(deviceDescription: [:], cgDisplayID: 11))
        #expect(ScreenMatcher.screenNumberKey.rawValue == "NSScreenNumber")
    }

    @Test func faceBoxConvertsVisionCoordinatesToViewCoordinates() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        // Bottom-left origin: a box in the lower-left quarter lands in the lower-left of the view.
        let rect = FaceBoxView.viewRect(for: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), in: frame)
        #expect(rect == CGRect(x: 0, y: 150, width: 200, height: 150))
    }

    @Test func brandColorsMatchTheContract() {
        #expect(SwayPalette.forestHex == 0x2F5D3A)
        #expect(SwayPalette.sageHex == 0x9CAF88)
        #expect(SwayPalette.ivoryHex == 0xF6F3EA)
        #expect(SwayPalette.charcoalHex == 0x2B2B2B)
    }
}

@Suite("Switch preview and calibration wording")
struct SwitchPreviewWordingTests {
    private let names: (DisplayID) -> String = { $0 == Fixtures.left.id ? "Left" : "Right" }

    @Test func theClassificationNamesTheNearestDisplayOrSaysWhyNot() {
        #expect(SwitchPreviewPresentation.classificationText(nil, name: names) == "No face")
        #expect(SwitchPreviewPresentation.classificationText(.noFace, name: names) == "No face")
        #expect(
            SwitchPreviewPresentation.classificationText(Fixtures.classification(.elsewhere), name: names)
                == "Looking elsewhere")
        #expect(
            SwitchPreviewPresentation.classificationText(Fixtures.classification(best: Fixtures.right.id), name: names)
                == "Nearest: Right")
    }

    @Test func theMarginBarOnlyExistsForADisplayAndStaysInRange() {
        #expect(SwitchPreviewPresentation.margin(nil) == nil)
        #expect(SwitchPreviewPresentation.margin(.noFace) == nil)
        #expect(SwitchPreviewPresentation.margin(Fixtures.classification(.elsewhere)) == nil)
        #expect(SwitchPreviewPresentation.margin(Fixtures.classification(margin: 0.62)) == 0.62)
        #expect(SwitchPreviewPresentation.margin(Fixtures.classification(margin: 1.4)) == 1)
        #expect(SwitchPreviewPresentation.margin(Fixtures.classification(margin: -0.2)) == 0)
    }

    @Test func thePhaseReadsWatchingDwellingCoolingOrLocked() {
        let phase = SwitchPreviewPresentation.phaseText
        #expect(phase(nil, names) == "Watching")
        #expect(phase(.idle, names) == "Watching")
        #expect(phase(.dwelling(display: Fixtures.right.id, progress: 0.4), names) == "Dwelling on Right")
        #expect(phase(.coolingDown(until: 3), names) == "Cooling down")
        #expect(phase(.locked, names) == "Switching is held")
    }

    @Test func theDwellBarOnlyExistsWhileDwelling() {
        #expect(SwitchPreviewPresentation.dwellProgress(.dwelling(display: Fixtures.left.id, progress: 0.25)) == 0.25)
        #expect(SwitchPreviewPresentation.dwellProgress(.dwelling(display: Fixtures.left.id, progress: 3)) == 1)
        #expect(SwitchPreviewPresentation.dwellProgress(.idle) == nil)
        #expect(SwitchPreviewPresentation.dwellProgress(.coolingDown(until: 1)) == nil)
        #expect(SwitchPreviewPresentation.dwellProgress(nil) == nil)
    }

    @Test func theFocusLineNamesTheDisplayOrSaysUnknown() {
        #expect(SwitchPreviewPresentation.focusText(Fixtures.left.id, name: names) == "Focus: Left")
        #expect(SwitchPreviewPresentation.focusText(nil, name: names) == "Focus: Unknown")
    }

    @Test func theHoldReasonsReadAsInTheContract() {
        #expect(TrackingHold.focusLock.text == "Focus Lock on")
        #expect(TrackingHold.swayInFront.text == "Sway is in front")
        #expect(TrackingHold.switching.text == "Switching\u{2026}")
        #expect(TrackingHold.focusTest.text == "Focus Test running")
    }

    @Test func theSwitchLogNamesTheAppAndTheDisplayNeverTheTitle() {
        let window = Fixtures.window(7, app: "Safari", title: "Secret page")
        let focused = FocusResult.focused(window, method: .accessibilityRaise, milliseconds: 120)
        let text = SwitchPreviewPresentation.logText(for: focused, display: "Right", held: 0.4)
        #expect(text == "Focused Safari on Right in 120 ms, held 0.40 s")
        #expect(!text.contains("Secret"))
        #expect(
            SwitchPreviewPresentation.logText(for: .noWindow(Fixtures.right.id), display: "Right", held: 0.4)
                == "No window on Right")
        #expect(
            SwitchPreviewPresentation.logText(
                for: .failed(window, reason: "Focus did not move to Safari"), display: "Right", held: 0)
                == "Failed: Focus did not move to Safari")
        #expect(
            SwitchPreviewPresentation.logText(for: .notTrusted, display: "Right", held: 0)
                == "Accessibility permission needed")
    }

    @Test func theMessagesMatchTheContract() {
        #expect(SwitchPreviewPresentation.noProfile == "Run the gate test to calibrate.")
        #expect(
            CalibrationError.tooFewDisplays.userMessage
                == "Not enough face samples on at least two displays to calibrate. Run the gate test with your face visible."
        )
        #expect(CalibrationError.featuresMissing(.visionAngles).userMessage == "This trace has no Vision angles")
        #expect(userMessage(for: CalibrationError.tooFewDisplays) == CalibrationError.tooFewDisplays.userMessage)
    }

    @Test func theLandmarkPlotExplainsItselfOnlyWhenFacesExistWithoutLandmarks() {
        let text = PlotPlaceholder.text
        let notice = "Landmark angles are computed only during the gate test."
        #expect(PlotPlaceholder.landmarksOnlyDuringGate == notice)
        // Faces are there, but none carries landmarks.
        #expect(text(.landmarkAngles, true, false, true) == notice)
        // Vision angles are always present with a face.
        #expect(text(.visionAngles, true, false, true) == "Waiting for a face\u{2026}")
        // No face yet.
        #expect(text(.landmarkAngles, false, false, true) == "Waiting for a face\u{2026}")
        #expect(text(.landmarkAngles, false, false, false) == "Turn the camera on to see live pose")
        // Something to draw.
        #expect(text(.landmarkAngles, true, true, true) == nil)
        #expect(text(.visionAngles, true, true, true) == nil)
    }
}

@Suite("Live content visibility")
struct LiveContentVisibilityTests {
    @Test func liveContentShowsOnlyInAnOpenUnminimizedWindow() {
        #expect(WindowVisibility.showsLiveContent(isVisible: true, isMiniaturized: false, isClosing: false))
        #expect(!WindowVisibility.showsLiveContent(isVisible: false, isMiniaturized: false, isClosing: false))
        #expect(!WindowVisibility.showsLiveContent(isVisible: true, isMiniaturized: true, isClosing: false))
        // `willClose` arrives while the window still reports itself visible.
        #expect(!WindowVisibility.showsLiveContent(isVisible: true, isMiniaturized: false, isClosing: true))
    }

    @Test func theLookLineIsOneShortLineInEveryState() {
        let label: (DisplayID) -> String = { $0 == Fixtures.left.id ? "Left" : "Right" }
        #expect(LookSummary(Fixtures.classification(best: Fixtures.right.id), label: label) == .display("Right"))
        #expect(LookSummary(Fixtures.classification(.elsewhere), label: label) == .elsewhere)
        #expect(LookSummary(.noFace, label: label) == .noFace)
        #expect(LookSummary.display("Right").text == "Looking at Right")
        #expect(LookSummary.elsewhere.text == "Looking elsewhere")
        #expect(LookSummary.noFace.text == "No face")
        // Camera off: a dash instead of no line, so the popover keeps its height.
        #expect(LookSummary.off.text == "\u{2014}")
    }
}
