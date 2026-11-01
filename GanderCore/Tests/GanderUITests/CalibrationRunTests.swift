import Foundation
import GanderModels
import Testing

@testable import GanderUI

@Suite("Calibration run settings and wording")
struct CalibrationRunTests {
    // MARK: Timing (SPEC D30)

    @Test func theCalibrationIsTwoRoundsOfTwoAndAHalfSecondHolds() {
        let configuration = GateTestConfiguration.calibration
        #expect(configuration.rounds == 2)
        #expect(configuration.holdDuration == 2.5)
        #expect(configuration.clamped == configuration)
        #expect(GateTestConfiguration.settleDuration == 1.5)
    }

    @Test func threeDisplaysTakeAboutTwentyFourSecondsAndTwoTakeSixteen() {
        #expect(GateTestConfiguration.calibration.estimatedDuration(displayCount: 3) == 24)
        #expect(GateTestConfiguration.calibration.estimatedDuration(displayCount: 2) == 16)
    }

    @Test func theGateTestWindowStillCannotHoldLessThanThreeSeconds() {
        #expect(GateTestConfiguration(rounds: 2, holdDuration: 2.5).holdDuration == 3)
        #expect(GateTestConfiguration.holdRange == 3...10)
        #expect(GateTestConfiguration().holdDuration == 5)
        #expect(GateTestConfiguration() != GateTestConfiguration.calibration)
    }

    @Test func aSessionOnTheCalibrationSettingsSettlesThenHoldsForTheRightTimes() {
        let clock = TestClock()
        var session = GateTestSession(
            layout: Fixtures.twoDisplays, cameraName: nil, configuration: .calibration, clock: clock.reading)
        #expect(session.steps.count == 4)
        session.start()

        clock.set(1.49)
        session.advance()
        #expect(session.phase == .settling)
        clock.set(1.5)
        session.advance()
        #expect(session.phase == .holding)
        #expect(session.progress?.phaseDuration == 2.5)

        clock.set(3.99)
        session.advance()
        #expect(session.phase == .holding)
        clock.set(4.0)
        session.advance()
        #expect(session.phase == .settling)
        #expect(session.currentStep?.display.id == Fixtures.right.id)
    }

    // MARK: Wording

    @Test func eachPurposeHasItsOwnNameAndInstruction() {
        #expect(GatePurpose.gateTest.noun == "gate test")
        #expect(GatePurpose.calibration.noun == "calibration")
        #expect(GatePurpose.gateTest.tryAgain == "Run the test again.")
        #expect(GatePurpose.calibration.tryAgain == "Calibrate again.")
    }

    @Test func theSetupTextsMatchTheSpec() {
        #expect(
            SetupPresentation.cameraAdvice
                == "Put the camera where it sees your face from every display. On top of the middle display works best."
        )
        #expect(SetupPresentation.needsSecondDisplay == "Connect a second display to calibrate.")
        #expect(SetupPresentation.calibrateLater.hasPrefix(SetupPresentation.needsSecondDisplay))
        #expect(SetupPresentation.calibrationCancelled == "Calibration cancelled.")
    }

    // MARK: The verdict

    private func pairs(_ values: [(DisplayID, DisplayID, Double)]) -> [PairSeparation] {
        values.map { PairSeparation(first: $0.0, second: $0.1, meanDistance: 10, dPrime: $0.2) }
    }

    private func names(_ id: DisplayID) -> String {
        ["display-left": "Left", "display-right": "Right", "display-far": "Far"][id.rawValue] ?? "?"
    }

    @Test func theWeakestPairIsTheOneNamed() {
        let three = pairs([
            (Fixtures.left.id, Fixtures.right.id, 9), (Fixtures.left.id, Fixtures.far.id, 14),
            (Fixtures.right.id, Fixtures.far.id, 2.5),
        ])

        let marginal = SetupResult(analysis: Fixtures.analysis(visionVerdict: .marginal, pairs: three), name: names)
        #expect(
            marginal.text
                == "Calibration saved. Right and Far are close together, so switching between them may be slower.")
        #expect(marginal.quality == .fair)
        #expect(marginal.isSaved)

        let noGo = SetupResult(analysis: Fixtures.analysis(visionVerdict: .noGo, pairs: three), name: names)
        #expect(
            noGo.text
                == "Calibration saved, but Right and Far are hard to tell apart. "
                + "Try moving the camera, then calibrate again.")
        #expect(noGo.quality == .poor)
        #expect(noGo.isSaved)
    }

    @Test func aVerdictWithoutAPairStillReads() {
        let marginal = SetupResult(analysis: Fixtures.analysis(visionVerdict: .marginal, pairs: []), name: names)
        let noGo = SetupResult(analysis: Fixtures.analysis(visionVerdict: .noGo, pairs: []), name: names)

        #expect(marginal.quality == .fair)
        #expect(marginal.text.hasPrefix("Calibration saved."))
        #expect(noGo.quality == .poor)
        #expect(noGo.text.hasSuffix("Try moving the camera, then calibrate again."))
    }

    @Test func noVisionReportAtAllReadsAsGood() {
        let landmarkOnly = GateAnalysis(
            reports: [Fixtures.report(.landmarkAngles, verdict: .noGo)], overall: .noGo,
            bestFeatureSet: .landmarkAngles, thresholds: .default)

        let result = SetupResult(analysis: landmarkOnly, name: names)

        #expect(result.quality == .good)
        #expect(result.text == "Calibration looks good.")
    }

    @Test func aFailedResultIsNotSaved() {
        let failed = SetupResult.failed("Because.")
        #expect(failed.quality == .failed)
        #expect(failed.text == "Because.")
        #expect(!failed.isSaved)
        #expect(SetupResult.good == "Calibration looks good.")
    }
}
