import AppKit
import Foundation
import SwayModels
import Testing

@testable import SwayUI

@Suite("Status presentation")
struct StatusPresentationTests {
    @Test(arguments: [
        (CaptureStatus.stopped, false, "eye.slash"),
        (CaptureStatus.starting, false, "eye"),
        (CaptureStatus.running(nil), true, "eye.fill"),
        (CaptureStatus.running(nil), false, "eye.trianglebadge.exclamationmark"),
        (CaptureStatus.suspended(.screenLocked), false, "pause.circle"),
        (CaptureStatus.interrupted("busy"), false, "exclamationmark.triangle"),
        (CaptureStatus.failed(.noDevice), false, "exclamationmark.triangle"),
    ])
    func menuBarSymbolFollowsTheContract(status: CaptureStatus, hasFace: Bool, symbol: String) {
        #expect(status.menuBarSymbol(hasFace: hasFace) == symbol)
    }

    @Test func statusLineNamesTheStateAndTheCamera() {
        #expect(CaptureStatus.stopped.statusLine(cameraName: "Cam") == "Camera off")
        #expect(CaptureStatus.starting.statusLine(cameraName: "Cam") == "Starting camera\u{2026}")
        #expect(
            CaptureStatus.running(Fixtures.builtInCamera).statusLine(cameraName: nil)
                == "Running \u{00B7} FaceTime HD Camera")
        #expect(CaptureStatus.running(nil).statusLine(cameraName: "Cam") == "Running \u{00B7} Cam")
        #expect(CaptureStatus.running(nil).statusLine(cameraName: nil) == "Running")
        #expect(CaptureStatus.suspended(.screenLocked).statusLine(cameraName: nil) == "Suspended: screen locked")
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
