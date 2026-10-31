import AppKit
import Observation
import SwayModels
import Testing
import os

@testable import SwayUI

@Suite("Menu prompts and rows")
struct MenuPromptTests {
    // MARK: Banner wording and buttons

    @Test func theCalibrationBannerTextsAndButtonMatchTheSpec() {
        #expect(MenuBanner.needsCalibrationText == "New display setup. Calibrate so Gander can switch between them.")
        #expect(MenuBanner.calibrateButtonTitle == "Calibrate (about 20 s)\u{2026}")
        #expect(
            MenuBanner.needsCameraCalibrationText(camera: "Logitech C922") == "No calibration for Logitech C922 yet.")
        #expect(MenuBanner.firstSetupText == "Gander needs a quick setup, about a minute.")
    }

    @Test func theSetupAndCalibrationBannersOpenTheSetupWindow() {
        #expect(MenuBanner.firstSetup.buttonWindowID == "setup")
        #expect(MenuBanner.needsCalibration.buttonWindowID == "setup")
        #expect(MenuBanner.needsCameraCalibration("Logitech C922").buttonWindowID == "setup")
        #expect(SwayWindowID.setup == "setup")
        #expect(SwayWindowID.settings == "settings")
    }

    @Test func theOtherBannersOpenNoWindow() {
        #expect(MenuBanner.cameraPermission.buttonWindowID == nil)
        #expect(MenuBanner.needsAccessibility.buttonWindowID == nil)
        #expect(MenuBanner.shortcut("Taken").buttonWindowID == nil)
    }

    // MARK: Which banner

    private func banner(_ edit: (inout MenuBanner.Facts) -> Void = { _ in }) -> MenuBanner? {
        var facts = MenuBanner.Facts(
            hasPermissionPrompt: false, libraryIsEmpty: false, trackingEnabled: true, displayCount: 2,
            hasCalibration: false, accessibilityTrusted: true, shortcutMessage: nil)
        edit(&facts)
        return MenuBanner.current(facts)
    }

    @Test func aCameraWithoutACalibrationGetsItsOwnBanner() {
        #expect(banner() == .needsCalibration)
        #expect(banner { $0.cameraWithoutCalibration = "Logitech C922" } == .needsCameraCalibration("Logitech C922"))
    }

    @Test func theCameraBannerFollowsTheSameConditionsAsTheNeedsCalibrationBanner() {
        #expect(
            banner {
                $0.cameraWithoutCalibration = "X"; $0.trackingEnabled = false
            } == nil)
        #expect(
            banner {
                $0.cameraWithoutCalibration = "X"; $0.displayCount = 1
            } == nil)
        #expect(
            banner {
                $0.cameraWithoutCalibration = "X"; $0.libraryIsEmpty = true
            } == .firstSetup)
        #expect(
            banner {
                $0.cameraWithoutCalibration = "X"; $0.hasPermissionPrompt = true
            } == .cameraPermission)
        #expect(
            banner {
                $0.cameraWithoutCalibration = "X"; $0.hasCalibration = true
            } == nil)
    }

    // MARK: The model's facts

    @MainActor
    @Test func anUnknownDisplaySetAsksForACalibration() {
        let h = Harness.make(layout: Fixtures.threeDisplays, trackingSaved: true) {
            Harness.seedLibrary([Fixtures.profile()], into: $0)
        }
        defer { h.tearDown() }

        #expect(h.model.menuBanner == .needsCalibration)
        #expect(h.model.cameraWithoutCalibration == nil)
    }

    @MainActor
    @Test func anotherCamerasCalibrationForTheseDisplaysAsksForOneForThisCamera() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        h.model.refreshAccessibilityTrust()
        #expect(h.model.menuBanner == nil)

        await h.model.selectCamera(Fixtures.externalCamera.id)

        #expect(h.model.cameraWithoutCalibration == "Logitech C922")
        #expect(h.model.menuBanner == .needsCameraCalibration("Logitech C922"))
        #expect(h.model.trackingStatus == .needsCalibration)

        await h.model.selectCamera(nil)
        #expect(h.model.menuBanner == nil)
    }

    @MainActor
    @Test func aCameraWithItsOwnCalibrationNeedsNoBanner() async {
        let h = Harness.make(
            calibrated: true, calibrationCameras: [Fixtures.builtInCamera.name, Fixtures.externalCamera.name])
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        h.model.refreshAccessibilityTrust()

        await h.model.selectCamera(Fixtures.externalCamera.id)

        #expect(h.model.menuBanner == nil)
        #expect(h.model.activeCalibration?.saved.cameraName == "Logitech C922")
    }

    @MainActor
    @Test func calibratingForTheNewCameraClearsTheBanner() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        await h.model.selectCamera(Fixtures.externalCamera.id)
        #expect(h.model.menuBanner == .needsCameraCalibration("Logitech C922"))
        h.engine.setFitResult(.success(Fixtures.profile(cameraName: Fixtures.externalCamera.name)))

        await h.openSetupOnCameraCheck()
        h.model.handle(.status(.running(Fixtures.externalCamera)))
        await h.completeCalibration()

        #expect(h.model.menuBanner == nil)
        #expect(h.model.library.profiles.count == 2)
    }

    @MainActor
    @Test func theNeedsCalibrationBannerIsOnlyReadWhenNothingFits() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        #expect(h.model.cameraWithoutCalibration == nil, "A calibration fits")
    }

    @MainActor
    @Test func theSetupAndSettingsStateDoesNotChangeAtTheFrameRate() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        h.run(frames: 1, dt: 1.0 / 15)
        let model = h.model
        let count = OSAllocatedUnfairLock(initialState: 0)

        withObservationTracking {
            _ =
                (
                    model.setupFlow, model.setupMessage, model.setupResult, model.framingAdvice, model.gatePurpose,
                    model.loginItemStatus, model.isRecordingShortcut, model.menuBanner, model.trackingStatus
                )
                as (
                    SetupFlow?, UserMessage?, SetupResult?, FramingAdvice, GatePurpose, LoginItemStatus, Bool,
                    MenuBanner?, TrackingStatus
                )
        } onChange: {
            count.withLock { $0 += 1 }
        }
        h.run(frames: 60, dt: 1.0 / 15)

        #expect(count.withLock { $0 } == 0)
    }

    // MARK: Menu rows

    @Test func theMenuRowsOpenTheirWindowsInTheOrderOfTheSpec() {
        #expect(
            MenuWindowItem.allCases.map(\.title) == [
                "Calibrate\u{2026}", "Settings\u{2026}", "Pose Debug Window\u{2026}", "Head-Pose Gate Test\u{2026}",
                "Focus Test Window\u{2026}",
            ])
        #expect(
            MenuWindowItem.allCases.map(\.windowID) == ["setup", "settings", "pose-debug", "gate-test", "focus-test"])
    }

    @Test func calibrateAndSettingsHaveTheirSymbolsAndEverySymbolResolves() {
        #expect(MenuWindowItem.calibrate.windowID == SwayWindowID.setup)
        #expect(MenuWindowItem.settings.systemImage == "gearshape")
        #expect(MenuWindowItem.settings.windowID == SwayWindowID.settings)
        #expect(MenuWindowItem.focusTest.systemImage == "rectangle.2.swap")
        for item in MenuWindowItem.allCases {
            #expect(
                NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil) != nil, "\(item.systemImage)"
            )
        }
    }
}
