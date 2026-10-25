import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel calibration library")
struct AppModelCalibrationTests {
    private let libraryKey = "sway.calibrationLibrary"
    private let oldKey = "sway.calibrationProfile"

    private func encoded(_ profile: CalibrationProfile) throws -> Data {
        try AppModel.encoder().encode(profile)
    }

    // MARK: Fitting and saving

    @Test func aProfileIsFittedAfterAGateAnalysisAndSavedInTheLibrary() async throws {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.library.profiles.isEmpty)

        await h.completeGateRun()

        let call = try #require(h.engine.fitCalls.first)
        #expect(h.engine.fitCalls.count == 1)
        #expect(call.features == .visionAngles)
        #expect(call.rounds == nil)
        #expect(call.trace == h.analyzer.analyzedTraces.first)
        #expect(h.model.library.profiles == [Fixtures.profile()])
        #expect(h.model.calibrationMessage == nil)
        #expect(h.storedLibrary()?.profiles == [Fixtures.profile()])
        #expect(h.model.activeCalibration?.saved == Fixtures.profile())
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
        #expect(h.model.library.profiles == [Fixtures.profile()])
        #expect(h.storedLibrary()?.profiles == [Fixtures.profile()])
    }

    @Test func aTraceThatCannotBeOpenedFitsNothing() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.store.setLoadError(.io("missing"))

        h.model.openTrace(at: URL(fileURLWithPath: "/tmp/sway-ui-tests/missing.json"))

        #expect(h.engine.fitCalls.isEmpty)
        #expect(h.model.library.profiles.isEmpty)
    }

    @Test func aFitFailureKeepsTheLibraryAndExplainsWhy() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        let kept = h.model.library
        #expect(!kept.profiles.isEmpty)

        h.engine.setFitResult(.failure(.tooFewDisplays))
        h.openTrace(name: "second.json")
        #expect(h.model.library == kept)
        #expect(
            h.model.calibrationMessage
                == .error(
                    "Not enough face samples on at least two displays to calibrate. Run the gate test with your face visible."
                ))
        #expect(h.storedLibrary() == kept)

        h.engine.setFitResult(.failure(.featuresMissing(.visionAngles)))
        h.openTrace(name: "third.json")
        #expect(h.model.library == kept)
        #expect(h.model.calibrationMessage == .error("This trace has no Vision angles"))
    }

    @Test func aFitFailureWithNoPreviousProfileLeavesTheLibraryEmpty() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))

        h.openTrace()

        #expect(h.model.library.profiles.isEmpty)
        #expect(h.model.activeCalibration == nil)
        #expect(h.model.calibrationMessage?.kind == .error)
        #expect(h.defaults.data(forKey: libraryKey) == nil)
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
        #expect(h.model.lastFittedProfile == Fixtures.profile())
        #expect(h.model.activeCalibration != nil)
    }

    @Test func aFailedGateFitStillShowsTheReport() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.engine.setFitResult(.failure(.tooFewDisplays))

        await h.completeGateRun()

        #expect(h.model.isShowingReport)
        #expect(h.model.library.profiles.isEmpty)
        #expect(h.model.calibrationMessage?.text.hasPrefix("Not enough face samples") == true)
    }

    @Test func aRefitForTheSameDisplaysAndCameraReplacesTheOldCalibration() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        let newer = Fixtures.profile(createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        h.engine.setFitResult(.success(newer))

        h.openTrace(name: "newer.json")

        #expect(h.model.library.profiles == [newer])
    }

    @Test func calibrationsForAnotherCameraAreKeptSideBySide() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        h.engine.setFitResult(.success(Fixtures.profile(cameraName: Fixtures.externalCamera.name)))

        h.openTrace(name: "external.json")

        #expect(h.model.library.profiles.count == 2)
        #expect(Set(h.model.library.profiles.map(\.cameraName)) == ["FaceTime HD Camera", "Logitech C922"])
    }

    // MARK: Restoring and migration

    @Test func theLibraryIsRestoredOnLaunch() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()

        let relaunched = h.relaunchedModel()

        #expect(relaunched.library.profiles == [Fixtures.profile()])
        #expect(relaunched.activeCalibration?.saved == Fixtures.profile())
    }

    @Test func storedDataThatDoesNotDecodeIsIgnored() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.defaults.set(Data("not json".utf8), forKey: libraryKey)

        #expect(h.relaunchedModel().library.profiles.isEmpty)

        h.defaults.set("a string, not data", forKey: libraryKey)
        #expect(h.relaunchedModel().library.profiles.isEmpty)
    }

    @Test func aLibraryWithAnotherFormatVersionIsIgnored() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        let json = #"{"formatVersion": 99, "profiles": []}"#
        h.defaults.set(Data(json.utf8), forKey: libraryKey)

        #expect(h.relaunchedModel().library.profiles.isEmpty)
    }

    @Test func theSingleProfileOfAnEarlierVersionMovesIntoTheLibraryAtLaunch() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        h.defaults.set(try encoded(Fixtures.profile()), forKey: oldKey)

        let relaunched = h.relaunchedModel()

        #expect(relaunched.library.profiles == [Fixtures.profile()])
        #expect(relaunched.activeCalibration != nil)
        #expect(h.storedLibrary()?.profiles == [Fixtures.profile()], "The library is persisted")
        #expect(h.defaults.object(forKey: oldKey) == nil, "The old key is removed")
    }

    @Test func anOldProfileInAnotherFormatVersionIsNotMigrated() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        let future = CalibrationProfile(
            formatVersion: CalibrationProfile.currentFormatVersion + 1, features: .visionAngles,
            displays: Fixtures.profile().displays, yawScale: 2, pitchScale: 2.5,
            layoutFingerprint: Fixtures.twoDisplays.fingerprint, cameraName: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        h.defaults.set(try encoded(future), forKey: oldKey)

        #expect(h.relaunchedModel().library.profiles.isEmpty)
    }

    @Test func anExistingLibraryWinsOverTheOldKey() throws {
        let h = Harness.make()
        defer { h.tearDown() }
        let current = Fixtures.profile(cameraName: Fixtures.externalCamera.name)
        Harness.seedLibrary([current], into: h.defaults)
        h.defaults.set(try encoded(Fixtures.profile()), forKey: oldKey)

        #expect(h.relaunchedModel().library.profiles == [current])
    }

    // MARK: Resolution

    @Test func theActiveCalibrationFollowsTheLayout() {
        let h = Harness.make(layout: Fixtures.threeDisplays, calibrated: true)
        defer { h.tearDown() }
        #expect(h.model.activeCalibration?.isPartial == false)
        #expect(h.model.activeCalibration?.profile.displays.count == 3)

        // A display is unplugged: tracking continues on the rest, with the same scales.
        h.model.layoutDidChange(Fixtures.twoDisplays)
        #expect(h.model.activeCalibration?.isPartial == true)
        #expect(h.model.activeCalibration?.profile.displayIDs == [Fixtures.left.id, Fixtures.right.id])
        #expect(h.model.activeCalibration?.saved.displays.count == 3)

        // Down to one display: nothing to switch between.
        h.model.layoutDidChange(Fixtures.oneDisplay)
        #expect(h.model.activeCalibration == nil)

        // A display this calibration has never seen: unknown.
        h.model.layoutDidChange(Fixtures.fourDisplays)
        #expect(h.model.activeCalibration == nil)

        h.model.layoutDidChange(Fixtures.threeDisplays)
        #expect(h.model.activeCalibration?.isPartial == false)
    }

    @Test func anArrangementChangeKeepsTheCalibration() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let moved = DisplayInfo(
            id: Fixtures.right.id, cgDisplayID: 12, name: "Right",
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
            isBuiltIn: false, isMain: false)

        h.model.layoutDidChange(DisplayLayout(displays: [Fixtures.left, moved]))

        #expect(
            h.model.activeCalibration != nil,
            "A resolution or position change does not move monitors relative to the camera")
    }

    @Test func theActiveCalibrationFollowsTheCamera() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(h.model.trackingCameraName == "FaceTime HD Camera")
        #expect(h.model.activeCalibration != nil)

        await h.model.selectCamera(Fixtures.externalCamera.id)
        #expect(h.model.trackingCameraName == "Logitech C922")
        #expect(h.model.activeCalibration == nil, "No calibration for this camera yet")

        await h.model.selectCamera(nil)
        #expect(h.model.activeCalibration != nil)
    }

    @Test func theCameraCaptureWouldPickDecidesWhenNothingRuns() {
        let h = Harness.make(savedCameraID: "unplugged-camera", calibrated: true)
        defer { h.tearDown() }
        // The selected device is not connected, so capture falls back to the first built-in camera.
        #expect(h.model.trackingCameraName == "FaceTime HD Camera")
        #expect(h.model.activeCalibration != nil)

        h.camera.setDevices([Fixtures.externalCamera])
        h.model.refreshEnvironment()
        #expect(h.model.trackingCameraName == "Logitech C922", "Else the first device")
        #expect(h.model.activeCalibration == nil)
    }

    @Test func theRunningCameraDecidesWhileItRuns() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.handle(.status(.running(Fixtures.externalCamera)))

        #expect(h.model.trackingCameraName == "Logitech C922")
        #expect(h.model.activeCalibration == nil)
    }

    @Test func aMissingCalibrationMakesTheStatusAskForOne() async {
        let h = Harness.make(layout: Fixtures.threeDisplays, trackingSaved: true) {
            Harness.seedLibrary([Fixtures.profile()], into: $0)
        }
        defer { h.tearDown() }

        #expect(h.model.activeCalibration == nil)
        #expect(h.model.trackingStatus == .needsCalibration)
        #expect(h.model.menuBanner == .needsCalibration)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 0, "Tracking waits with the camera off")
    }

    // MARK: Camera follows the calibration

    @Test func theCameraStartsAndStopsAsACalibrationAppearsAndDisappears() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }

        await h.model.setTrackingEnabled(true)
        #expect(h.pose.startCount == 0, "Tracking is on but nothing is calibrated")
        #expect(!h.model.isCameraActive)
        #expect(h.model.trackingStatus == .needsCalibration)

        h.openTrace()
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 1)
        #expect(h.model.isCameraActive)

        h.model.layoutDidChange(Fixtures.threeDisplays)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive, "An unknown display set stops the camera")
        #expect(h.pose.stopCount >= 1)

        h.model.layoutDidChange(Fixtures.twoDisplays)
        await h.model.cameraOperation?.value
        #expect(h.pose.startCount == 2)
        #expect(h.model.isCameraActive)
    }

    @Test func aCalibrationAppearingWhileTrackingIsOffDoesNotStartTheCamera() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }

        h.openTrace()
        await h.model.cameraOperation?.value

        #expect(h.pose.startCount == 0)
    }

    @Test func choosingACameraWithoutACalibrationStopsTheCameraAndChoosingBackRestartsIt() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        await h.model.selectCamera(Fixtures.externalCamera.id)
        await h.model.cameraOperation?.value
        #expect(!h.model.isCameraActive)
        #expect(h.model.trackingStatus == .needsCalibration)

        await h.model.selectCamera(nil)
        await h.model.cameraOperation?.value
        #expect(h.model.isCameraActive)
        let again = await waitUntil { h.model.status.isRunning }
        #expect(again)
    }

    @Test func removingTheActiveCalibrationStopsTheCamera() async throws {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        let key = try #require(h.model.activeCalibration?.saved.key)

        h.model.removeFromLibrary(key)
        await h.model.cameraOperation?.value

        #expect(h.model.library.profiles.isEmpty)
        #expect(h.storedLibrary()?.profiles.isEmpty == true)
        #expect(h.model.activeCalibration == nil)
        #expect(!h.model.isCameraActive)
    }

    // MARK: Decider

    @Test func aNewCalibrationGetsANewDeciderWithDefaultSettings() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.engine.recorders.isEmpty, "Nothing is calibrated yet")

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

    @Test func aChangedProfileRebuildsTheDecider() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()

        let changed = Fixtures.profile(createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        h.engine.setFitResult(.success(changed))
        h.openTrace(name: "newer.json")

        #expect(h.model.activeCalibration?.saved == changed)
        #expect(h.engine.recorders.count == 2)
        #expect(h.engine.lastRecorder?.profile == changed)
    }

    @Test func aPartialMatchClassifiesAgainstOnlyTheConnectedDisplays() {
        let h = Harness.make(layout: Fixtures.threeDisplays, calibrated: true)
        defer { h.tearDown() }
        #expect(h.engine.lastRecorder?.profile.displays.count == 3)

        h.model.layoutDidChange(Fixtures.twoDisplays)

        #expect(h.engine.lastRecorder?.profile.displayIDs == [Fixtures.left.id, Fixtures.right.id])
        #expect(h.engine.recorders.count == 2)
    }
}
