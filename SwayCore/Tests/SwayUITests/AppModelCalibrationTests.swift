import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel calibration profile")
struct AppModelCalibrationTests {
    private let key = "sway.calibrationProfile"

    private func decodedProfile(in defaults: UserDefaults) -> CalibrationProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CalibrationProfile.self, from: data)
    }

    // MARK: Fitting

    @Test func aProfileIsFittedAfterAGateAnalysisAndPersisted() async throws {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.calibrationProfile == nil)

        await h.completeGateRun()

        let call = try #require(h.engine.fitCalls.first)
        #expect(h.engine.fitCalls.count == 1)
        #expect(call.features == .visionAngles)
        #expect(call.rounds == nil)
        #expect(call.trace == h.analyzer.analyzedTraces.first)
        #expect(h.model.calibrationProfile == Fixtures.profile())
        #expect(h.model.calibrationMessage == nil)
        #expect(decodedProfile(in: h.defaults) == Fixtures.profile())
    }

    @Test func aProfileIsFittedAfterAnOpenedTrace() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        let trace = Fixtures.trace()

        h.openTrace(trace)

        let call = try #require(h.engine.fitCalls.first)
        #expect(call.trace == trace)
        #expect(call.features == .visionAngles)
        #expect(call.rounds == nil)
        #expect(h.model.calibrationProfile == Fixtures.profile())
        #expect(decodedProfile(in: h.defaults) == Fixtures.profile())
    }

    @Test func aTraceThatCannotBeOpenedFitsNothing() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.store.setLoadError(.io("missing"))

        h.model.openTrace(at: URL(fileURLWithPath: "/tmp/sway-ui-tests/missing.json"))

        #expect(h.engine.fitCalls.isEmpty)
        #expect(h.model.calibrationProfile == nil)
    }

    @Test func aFitFailureKeepsThePreviousProfileAndExplainsWhy() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        let kept = h.model.calibrationProfile
        #expect(kept != nil)

        h.engine.setFitResult(.failure(.tooFewDisplays))
        h.openTrace(name: "second.json")
        #expect(h.model.calibrationProfile == kept)
        #expect(
            h.model.calibrationMessage
                == .error(
                    "Not enough face samples on at least two displays to calibrate. Run the gate test with your face visible."
                ))
        #expect(decodedProfile(in: h.defaults) == kept)

        h.engine.setFitResult(.failure(.featuresMissing(.visionAngles)))
        h.openTrace(name: "third.json")
        #expect(h.model.calibrationProfile == kept)
        #expect(h.model.calibrationMessage == .error("This trace has no Vision angles"))
    }

    @Test func aFitFailureWithNoPreviousProfileLeavesTheModelUncalibrated() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))

        h.openTrace()

        #expect(h.model.calibrationProfile == nil)
        #expect(h.model.calibrationMessage?.kind == .error)
        #expect(h.defaults.data(forKey: key) == nil)
        // The analysis itself is still adopted: only the calibration failed.
        #expect(h.model.analysis != nil)
    }

    @Test func aLaterSuccessfulFitClearsTheMessage() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))
        h.openTrace()
        #expect(h.model.calibrationMessage != nil)

        h.engine.setFitResult(.success(Fixtures.profile()))
        h.openTrace(name: "again.json")

        #expect(h.model.calibrationMessage == nil)
        #expect(h.model.calibrationProfile != nil)
    }

    @Test func aFailedGateFitStillShowsTheReport() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))

        await h.completeGateRun()

        #expect(h.model.isShowingReport)
        #expect(h.model.calibrationProfile == nil)
        #expect(h.model.calibrationMessage?.text.hasPrefix("Not enough face samples") == true)
    }

    // MARK: Restoring

    @Test func theProfileIsRestoredOnLaunch() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()

        let relaunched = h.relaunchedModel()

        #expect(relaunched.calibrationProfile == Fixtures.profile())
        #expect(!relaunched.isCalibrationStale)
    }

    @Test func storedDataThatDoesNotDecodeIsIgnored() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.defaults.set(Data("not json".utf8), forKey: key)

        #expect(h.relaunchedModel().calibrationProfile == nil)

        h.defaults.set("a string, not data", forKey: key)
        #expect(h.relaunchedModel().calibrationProfile == nil)
    }

    @Test func aProfileWithAnotherFormatVersionIsIgnored() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        let future = CalibrationProfile(
            formatVersion: CalibrationProfile.currentFormatVersion + 1, features: .visionAngles,
            displays: Fixtures.profile().displays, yawScale: 2, pitchScale: 2.5,
            layoutFingerprint: Fixtures.twoDisplays.fingerprint, cameraName: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        h.defaults.set(try encoder.encode(future), forKey: key)

        #expect(h.relaunchedModel().calibrationProfile == nil)
    }

    // MARK: Stale flag

    @Test func theStaleFlagFollowsTheLayout() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(!h.model.isCalibrationStale, "No profile is missing, not stale")

        h.openTrace()
        #expect(!h.model.isCalibrationStale)

        h.model.layoutDidChange(Fixtures.threeDisplays)
        #expect(h.model.isCalibrationStale)

        h.model.layoutDidChange(Fixtures.twoDisplays)
        #expect(!h.model.isCalibrationStale)
    }

    @Test func aRestoredProfileIsStaleOnAnotherLayout() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()

        #expect(h.relaunchedModel(layout: Fixtures.threeDisplays).isCalibrationStale)
    }

    // MARK: Decider

    @Test func aNewProfileGetsANewDeciderWithDefaultSettings() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()

        let recorder = h.engine.lastRecorder
        #expect(h.engine.recorders.count == 1)
        #expect(recorder?.profile == Fixtures.profile())
        #expect(recorder?.settings == .default)
    }

    @Test func refittingTheSameProfileKeepsTheRunningDecider() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        h.openTrace(name: "same.json")

        #expect(h.engine.fitCalls.count == 2)
        #expect(h.engine.recorders.count == 1)
    }

    @Test func aChangedProfileRebuildsTheDeciderAndForgetsTheSimulatedFocus() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        h.model.simulatedFocus = Fixtures.right.id

        let changed = Fixtures.profile(createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        h.engine.setFitResult(.success(changed))
        h.openTrace(name: "newer.json")

        #expect(h.model.calibrationProfile == changed)
        #expect(h.engine.recorders.count == 2)
        #expect(h.engine.lastRecorder?.profile == changed)
        #expect(h.model.simulatedFocus == nil)
    }
}
