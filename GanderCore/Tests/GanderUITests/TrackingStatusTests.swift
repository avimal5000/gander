import AppKit
import Foundation
import GanderModels
import Testing

@testable import GanderUI

@Suite("Tracking status")
struct TrackingStatusTests {
    /// Tracking on and healthy: running, two displays, calibrated, trusted, a face.
    private func status(_ edit: (inout TrackingStatus.Snapshot) -> Void = { _ in }) -> TrackingStatus {
        var snapshot = TrackingStatus.Snapshot(
            authorization: .authorized, capture: .running(Fixtures.builtInCamera), trackingEnabled: true,
            calibrationRunning: false, displayCount: 2, hasCalibration: true, accessibilityTrusted: true,
            focusLocked: false, hasFace: true)
        edit(&snapshot)
        return TrackingStatus(snapshot)
    }

    // MARK: Every row of the table

    @Test func eachRowOfTheTableHasItsSymbolAndLine() {
        let rows: [(TrackingStatus, String, String)] = [
            (status { $0.authorization = .denied }, "exclamationmark.triangle", "Camera access needed"),
            (status { $0.authorization = .restricted }, "exclamationmark.triangle", "Camera access needed"),
            (status { $0.capture = .failed(.noDevice) }, "exclamationmark.triangle", "Camera unavailable"),
            (status { $0.trackingEnabled = false }, "eye.slash", "Paused"),
            (status { $0.calibrationRunning = true }, "scope", "Calibrating"),
            (status { $0.displayCount = 1 }, "display", "Only one display"),
            (status { $0.hasCalibration = false }, "questionmark.circle", "Needs calibration"),
            (status { $0.capture = .suspended(.screenLocked) }, "pause.circle", "Suspended: screen locked"),
            (status { $0.capture = .suspended(.systemSleep) }, "pause.circle", "Suspended: system asleep"),
            (status { $0.capture = .suspended(.displaysAsleep) }, "pause.circle", "Suspended: displays asleep"),
            (status { $0.capture = .starting }, "eye", "Starting camera"),
            (
                status { $0.capture = .interrupted("Camera is in use by another app") },
                "exclamationmark.triangle", "Camera busy"
            ),
            (
                status { $0.capture = .interrupted("Camera disconnected") },
                "exclamationmark.triangle", "Interrupted: Camera disconnected"
            ),
            (status { $0.accessibilityTrusted = false }, "hand.raised", "Needs Accessibility"),
            (status { $0.focusLocked = true }, "lock.fill", "Focus Lock on"),
            (status(), "eye.fill", "Tracking"),
            (status { $0.hasFace = false }, "eye.trianglebadge.exclamationmark", "No face"),
        ]
        for (row, symbol, line) in rows {
            #expect(row.symbol == symbol, "\(row)")
            #expect(row.line == line, "\(row)")
        }
    }

    @Test func theCasesAreTheOnesTheTableNames() {
        #expect(status { $0.authorization = .denied } == .cameraBlocked)
        #expect(status { $0.capture = .failed(.noDevice) } == .cameraFailed)
        #expect(status { $0.trackingEnabled = false } == .paused)
        #expect(status { $0.calibrationRunning = true } == .calibrating)
        #expect(status { $0.displayCount = 1 } == .oneDisplay)
        #expect(status { $0.hasCalibration = false } == .needsCalibration)
        #expect(status { $0.capture = .suspended(.screenLocked) } == .suspended(.screenLocked))
        #expect(status { $0.capture = .starting } == .starting)
        #expect(status { $0.capture = .interrupted("x") } == .cameraBusy("x"))
        #expect(status { $0.accessibilityTrusted = false } == .needsAccessibility)
        #expect(status { $0.focusLocked = true } == .focusLock)
        #expect(status() == .tracking)
        #expect(status { $0.hasFace = false } == .noFace)
    }

    @Test func everySymbolResolvesAsASystemSymbol() {
        let all: [TrackingStatus] = [
            .cameraBlocked, .cameraFailed, .paused, .calibrating, .oneDisplay, .needsCalibration,
            .suspended(.screenLocked), .starting, .cameraBusy("x"), .cameraDisconnected("Logitech C922"),
            .needsAccessibility, .focusLock, .tracking, .noFace,
        ]
        for status in all {
            #expect(
                NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil) != nil,
                "\(status.symbol) must exist")
        }
    }

    // MARK: Priority between neighbors

    @Test func cameraBlockedBeatsCameraFailed() {
        #expect(
            status {
                $0.authorization = .denied; $0.capture = .failed(.noDevice)
            } == .cameraBlocked)
    }

    @Test func aBlockedCameraOnlyCountsWhileTrackingIsOn() {
        #expect(
            status {
                $0.authorization = .denied; $0.trackingEnabled = false
            } == .paused)
        #expect(
            status {
                $0.authorization = .restricted; $0.trackingEnabled = false
            } == .paused)
        #expect(status { $0.authorization = .notDetermined } == .tracking)
    }

    @Test func cameraFailedBeatsPausedBecauseTheFailureTurnedTrackingOff() {
        #expect(
            status {
                $0.trackingEnabled = false; $0.capture = .failed(.noDevice)
            } == .cameraFailed)
    }

    @Test func calibratingShowsEvenWithTrackingOffAndBeatsTheRowsBelowIt() {
        #expect(
            status {
                $0.trackingEnabled = false; $0.calibrationRunning = true
            } == .calibrating)
        #expect(
            status {
                $0.calibrationRunning = true; $0.displayCount = 1; $0.hasCalibration = false
            } == .calibrating)
    }

    @Test func pausedBeatsEverythingBelowIt() {
        #expect(
            status {
                $0.trackingEnabled = false; $0.displayCount = 1; $0.hasCalibration = false; $0.focusLocked = true
            }
                == .paused)
    }

    @Test func oneDisplayBeatsNeedsCalibration() {
        #expect(
            status {
                $0.displayCount = 1; $0.hasCalibration = false
            } == .oneDisplay)
        #expect(status { $0.displayCount = 0 } == .oneDisplay)
    }

    @Test func needsCalibrationBeatsTheCameraStates() {
        #expect(
            status {
                $0.hasCalibration = false; $0.capture = .suspended(.screenLocked)
            } == .needsCalibration)
        #expect(
            status {
                $0.hasCalibration = false; $0.capture = .running(nil)
            } == .needsCalibration)
    }

    @Test func suspendedStartingAndBusyBeatNeedsAccessibility() {
        #expect(
            status {
                $0.accessibilityTrusted = false; $0.capture = .suspended(.systemSleep)
            } == .suspended(.systemSleep))
        #expect(
            status {
                $0.accessibilityTrusted = false; $0.capture = .starting
            } == .starting)
        #expect(
            status {
                $0.accessibilityTrusted = false; $0.capture = .interrupted("x")
            } == .cameraBusy("x"))
    }

    @Test func needsAccessibilityBeatsFocusLockWhichBeatsTrackingAndNoFace() {
        #expect(
            status {
                $0.accessibilityTrusted = false; $0.focusLocked = true
            } == .needsAccessibility)
        #expect(
            status {
                $0.focusLocked = true; $0.hasFace = false
            } == .focusLock)
    }

    // MARK: M7 additions

    @Test func anotherUsersSessionIsSuspendedWithItsOwnText() {
        let session = status { $0.capture = .suspended(.sessionInactive) }
        #expect(session == .suspended(.sessionInactive))
        #expect(session.symbol == "pause.circle")
        #expect(session.line == "Suspended: another user's session")
    }

    @Test func anUnpluggedChosenCameraNamesItselfWhileCaptureIsInterrupted() {
        let waiting = status {
            $0.capture = .interrupted("Camera disconnected"); $0.disconnectedCamera = "Logitech C922"
        }
        #expect(waiting == .cameraDisconnected("Logitech C922"))
        #expect(waiting.line == "Logitech C922 disconnected")
        #expect(waiting.symbol == "exclamationmark.triangle")
        #expect(waiting.tone == .problem)
        #expect(MenuBarGlyph(waiting) == .attention)
    }

    @Test func trackingTurnedOffForAnUnpluggedCameraNamesItInsteadOfPaused() {
        let lost = status {
            $0.trackingEnabled = false; $0.capture = .stopped; $0.disconnectedCamera = "Logitech C922"
        }
        #expect(lost == .cameraDisconnected("Logitech C922"))
        #expect(lost.line == "Logitech C922 disconnected")
        #expect(MenuBarGlyph(lost) == .attention)
        #expect(
            status {
                $0.trackingEnabled = false; $0.capture = .stopped
            } == .paused, "No lost camera: Paused")
    }

    @Test func aRunningCalibrationOrAFailedCameraBeatsTheLostCameraWhileTrackingIsOff() {
        #expect(
            status {
                $0.trackingEnabled = false; $0.disconnectedCamera = "Logitech C922"; $0.calibrationRunning = true
            } == .calibrating)
        #expect(
            status {
                $0.trackingEnabled = false; $0.disconnectedCamera = "Logitech C922"; $0.capture = .failed(.noDevice)
            } == .cameraFailed)
    }

    @Test func theUnpluggedCameraOnlyCountsWhileCaptureIsInterruptedAndNothingBeatsItAbove() {
        #expect(status { $0.disconnectedCamera = "Logitech C922" } == .tracking, "Running: the stand-in works")
        #expect(
            status {
                $0.capture = .suspended(.systemSleep); $0.disconnectedCamera = "Logitech C922"
            } == .suspended(.systemSleep))
        #expect(
            status {
                $0.capture = .interrupted("x"); $0.disconnectedCamera = "Logitech C922"; $0.hasCalibration = false
            } == .needsCalibration)
        #expect(
            status {
                $0.capture = .interrupted("x"); $0.disconnectedCamera = "Logitech C922"; $0.accessibilityTrusted = false
            } == .cameraDisconnected("Logitech C922"))
    }

    @Test func aStoppedCameraWithTrackingOnAndACalibrationIsAboutToStart() {
        #expect(status { $0.capture = .stopped } == .starting)
    }

    // MARK: Wording

    @Test func onlyTheCameraServicesInUseWordingCountsAsAnotherAppHavingTheCamera() {
        #expect(TrackingStatus.isUsedByAnotherApp("Camera is in use by another app"))
        #expect(!TrackingStatus.isUsedByAnotherApp("No frames received from the camera"))
        #expect(!TrackingStatus.isUsedByAnotherApp("Camera disconnected"))
    }

    @Test func theToneFollowsTheSeverity() {
        #expect(TrackingStatus.cameraBlocked.tone == .problem)
        #expect(TrackingStatus.cameraBusy("x").tone == .problem)
        #expect(TrackingStatus.paused.tone == .idle)
        #expect(TrackingStatus.needsCalibration.tone == .attention)
        #expect(TrackingStatus.tracking.tone == .active)
        #expect(TrackingStatus.focusLock.tone == .active)
    }
}

@Suite("Menu banners")
struct MenuBannerTests {
    private func banner(_ edit: (inout MenuBanner.Facts) -> Void = { _ in }) -> MenuBanner? {
        var facts = MenuBanner.Facts(
            hasPermissionPrompt: false, libraryIsEmpty: false, trackingEnabled: true, displayCount: 2,
            hasCalibration: true, accessibilityTrusted: true, shortcutMessage: nil)
        edit(&facts)
        return MenuBanner.current(facts)
    }

    @Test func nothingIsShownWhenAllIsWell() {
        #expect(banner() == nil)
    }

    @Test func eachBannerAppearsOnItsOwn() {
        #expect(banner { $0.hasPermissionPrompt = true } == .cameraPermission)
        #expect(banner { $0.libraryIsEmpty = true } == .firstSetup)
        #expect(banner { $0.hasCalibration = false } == .needsCalibration)
        #expect(banner { $0.accessibilityTrusted = false } == .needsAccessibility)
        #expect(banner { $0.shortcutMessage = "Taken" } == .shortcut("Taken"))
    }

    @Test func atMostOneBannerShowsInTheOrderOfTheContract() {
        #expect(
            banner {
                $0.hasPermissionPrompt = true; $0.libraryIsEmpty = true; $0.hasCalibration = false
                $0.accessibilityTrusted = false; $0.shortcutMessage = "Taken"
            } == .cameraPermission)
        #expect(
            banner {
                $0.libraryIsEmpty = true; $0.hasCalibration = false; $0.accessibilityTrusted = false
                $0.shortcutMessage = "Taken"
            } == .firstSetup)
        #expect(
            banner {
                $0.hasCalibration = false; $0.accessibilityTrusted = false; $0.shortcutMessage = "Taken"
            }
                == .needsCalibration)
        #expect(
            banner {
                $0.accessibilityTrusted = false; $0.shortcutMessage = "Taken"
            } == .needsAccessibility)
    }

    @Test func needsCalibrationNeedsTrackingOnAndTwoOrMoreDisplays() {
        #expect(
            banner {
                $0.hasCalibration = false; $0.trackingEnabled = false
            } == nil)
        #expect(
            banner {
                $0.hasCalibration = false; $0.displayCount = 1
            } == nil)
    }

    @Test func needsAccessibilityNeedsTrackingOnAndACalibration() {
        #expect(
            banner {
                $0.accessibilityTrusted = false; $0.trackingEnabled = false
            } == nil)
        #expect(
            banner {
                $0.accessibilityTrusted = false; $0.hasCalibration = false
            } == .needsCalibration)
        #expect(
            banner {
                $0.accessibilityTrusted = false; $0.hasCalibration = false; $0.displayCount = 1
            } == nil)
    }

    @Test func theTextsMatchTheSpec() {
        #expect(MenuBanner.firstSetupText == "Gander needs a quick setup, about a minute.")
        #expect(MenuBanner.needsCalibrationText == "New display setup. Calibrate so Gander can switch between them.")
        #expect(MenuBanner.needsAccessibilityText.hasPrefix("Gander needs Accessibility access"))
    }
}
