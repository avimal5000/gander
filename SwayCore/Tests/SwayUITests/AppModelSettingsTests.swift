import AppKit
import Foundation
import Observation
import SwayModels
import Testing
import os

@testable import SwayUI

@MainActor
@Suite("AppModel Settings window")
struct AppModelSettingsTests {
    private let shortcutKey = "sway.focusLockShortcut"
    private let optionCommandK = HotKeyShortcut(keyCode: 40, modifiers: [.option, .command], keyLabel: "K")

    private func pressOptionCommandK(_ h: Harness) {
        h.keyMonitor.press(40, [.option, .command], characters: "k")
    }

    // MARK: Switching sensitivity

    @Test func theSliderValuesSnapToTheGridAndStayInRange() {
        #expect(SensitivityPresentation.snappedDwell(0.4) == 0.4)
        #expect(SensitivityPresentation.snappedDwell(0.42) == 0.4)
        #expect(abs(SensitivityPresentation.snappedDwell(0.43) - 0.45) < 1e-9)
        #expect(SensitivityPresentation.snappedDwell(0) == 0.05)
        #expect(SensitivityPresentation.snappedDwell(0.07) == 0.05)
        #expect(SensitivityPresentation.snappedDwell(0.08) == 0.1)
        #expect(SensitivityPresentation.snappedDwell(9) == 1.5)
        #expect(SensitivityPresentation.dwellStep == 0.05)
        #expect(SwitchSensitivity.dwellRange == 0.05...1.5)
    }

    @Test func thePauseSliderValuesSnapToTheGridAndStayInRange() {
        #expect(SensitivityPresentation.snappedCooldown(0.75) == 0.75)
        #expect(SensitivityPresentation.snappedCooldown(0.77) == 0.75)
        #expect(SensitivityPresentation.snappedCooldown(0.78) == 0.8)
        #expect(SensitivityPresentation.snappedCooldown(0.3) == 0.3, "No 0.30000000000000004")
        #expect(SensitivityPresentation.snappedCooldown(0.1) == 0.2)
        #expect(SensitivityPresentation.snappedCooldown(0) == 0.2)
        #expect(SensitivityPresentation.snappedCooldown(9) == 1.5)
        #expect(SensitivityPresentation.cooldownStep == 0.05)
        #expect(SwitchSensitivity.cooldownRange == 0.2...1.5)
    }

    @Test func everyStepOfEitherSliderIsKeptExactly() {
        for step in 1...30 {
            let value = Double(step) / 20
            #expect(SensitivityPresentation.snappedDwell(value) == value, "Hold time \(value)")
            if SwitchSensitivity.cooldownRange.contains(value) {
                #expect(SensitivityPresentation.snappedCooldown(value) == value, "Pause \(value)")
            }
        }
    }

    @Test func theHoldTimeIsShownWithTwoDecimals() {
        #expect(SensitivityPresentation.dwellText(0.4) == "0.40 s")
        #expect(SensitivityPresentation.dwellText(1.5) == "1.50 s")
        #expect(SensitivityPresentation.dwellText(0.2) == "0.20 s")
        #expect(SensitivityPresentation.dwellText(0.05) == "0.05 s")
    }

    @Test func thePauseIsShownInTheSameFormatAsTheHoldTime() {
        #expect(SensitivityPresentation.cooldownText(0.75) == "0.75 s")
        #expect(SensitivityPresentation.cooldownText(0.3) == "0.30 s")
        #expect(SensitivityPresentation.cooldownText(1.5) == "1.50 s")
        #expect(SensitivityPresentation.cooldownText(0.2) == "0.20 s")
        #expect(SensitivityPresentation.cooldownText(0.75) == SensitivityPresentation.dwellText(0.75))
    }

    @Test func theInstantButtonsTooltipNamesTheTimingAndTheConfidence() {
        #expect(
            SensitivityPresentation.instantHelp
                == "Hold time 0.10 s and pause 0.30 s. Switch confidence stays as it is.")
    }

    @Test func theLogLineNamesTheHoldTimeThePauseAndTheConfidenceStepAndNothingElse() {
        #expect(
            SensitivityPresentation.logLine(SwitchSensitivity(dwell: 0.1, cooldown: 0.3, confidenceLevel: 1))
                == "Switching settings: hold 0.10 s, pause 0.30 s, confidence Easy")
        #expect(
            SensitivityPresentation.logLine(.default)
                == "Switching settings: hold 0.40 s, pause 0.75 s, confidence Balanced")
        #expect(
            SensitivityPresentation.logLine(SwitchSensitivity(dwell: 1.5, cooldown: 1.5, confidenceLevel: 4))
                == "Switching settings: hold 1.50 s, pause 1.50 s, confidence Strict")
    }

    @Test func theConfidenceSliderHasFiveNamedSteps() {
        #expect(SensitivityPresentation.confidenceNames.count == 5)
        #expect(SensitivityPresentation.confidenceNames.first == "Relaxed")
        #expect(SensitivityPresentation.confidenceNames.last == "Strict")
        #expect(SensitivityPresentation.confidenceRange == 0...4)
        #expect(SensitivityPresentation.confidenceNames.count == SwitchSensitivity.confidenceMargins.count)
        #expect(SensitivityPresentation.confidenceName(-3) == "Relaxed")
        #expect(SensitivityPresentation.confidenceName(9) == "Strict")
        #expect(SensitivityPresentation.confidenceName(SwitchSensitivity.default.confidenceLevel) == "Balanced")
    }

    @Test func changingTheHoldTimeSavesItAndRebuildsTheDeciderAtOnce() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let recorders = h.engine.recorders.count

        h.model.setHoldTime(0.8)

        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.8, confidenceLevel: 2))
        let settings = try #require(h.engine.lastRecorder?.settings)
        #expect(h.engine.recorders.count == recorders + 1)
        #expect(settings.dwell == 0.8)
        #expect(settings.enterMargin == SwitchSensitivity.default.switchSettings().enterMargin)
        #expect(h.relaunchedModel().sensitivity == SwitchSensitivity(dwell: 0.8, confidenceLevel: 2))
    }

    @Test func theHoldTimeSnapsToTheSlidersSteps() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setHoldTime(0.62)

        #expect(abs(h.model.sensitivity.dwell - 0.6) < 1e-9)
    }

    @Test func changingTheConfidenceMapsToTheEnterAndStayMargins() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        for (level, enter) in [(0, 0.15), (1, 0.225), (2, 0.30), (3, 0.375), (4, 0.45)] {
            h.model.setSwitchConfidence(level)
            let settings = try #require(h.engine.lastRecorder?.settings)
            #expect(settings.enterMargin == enter, "Level \(level)")
            #expect(settings.stayMargin == enter / 2, "Level \(level)")
            #expect(settings.dwell == 0.4, "The hold time is untouched")
        }
        #expect(h.model.sensitivity.confidenceLevel == 4)
    }

    @Test func aValueOutsideTheRangeIsClamped() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setSwitchConfidence(12)
        h.model.setHoldTime(30)

        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 1.5, confidenceLevel: 4))

        h.model.setHoldTime(-1)
        h.model.setCooldown(30)
        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.05, cooldown: 1.5, confidenceLevel: 4))
        h.model.setCooldown(-30)
        #expect(h.model.sensitivity.cooldown == 0.2)
    }

    @Test func changingThePauseSavesItAndRebuildsTheDeciderAtOnce() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let recorders = h.engine.recorders.count

        h.model.setCooldown(0.5)

        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.4, cooldown: 0.5, confidenceLevel: 2))
        let settings = try #require(h.engine.lastRecorder?.settings)
        #expect(h.engine.recorders.count == recorders + 1)
        #expect(settings.cooldown == 0.5)
        #expect(settings.dwell == 0.4, "The hold time is untouched")
        #expect(settings.enterMargin == SwitchSensitivity.default.switchSettings().enterMargin)
        let stored = try #require(h.defaults.data(forKey: "sway.switchSensitivity"))
        let saved = try #require(try? JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(saved["cooldown"] as? Double == 0.5)
        #expect(h.relaunchedModel().sensitivity == SwitchSensitivity(dwell: 0.4, cooldown: 0.5, confidenceLevel: 2))
    }

    @Test func thePauseSnapsToTheSlidersSteps() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setCooldown(0.62)
        #expect(h.model.sensitivity.cooldown == 0.6)

        h.model.setCooldown(0.3)
        #expect(h.model.sensitivity.cooldown == 0.3)
    }

    @Test func eachSliderLeavesTheOtherTwoAlone() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.setSensitivity(SwitchSensitivity(dwell: 0.6, cooldown: 1.1, confidenceLevel: 3))

        h.model.setHoldTime(0.9)
        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.9, cooldown: 1.1, confidenceLevel: 3))
        h.model.setCooldown(0.45)
        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.9, cooldown: 0.45, confidenceLevel: 3))
        h.model.setSwitchConfidence(0)
        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.9, cooldown: 0.45, confidenceLevel: 0))
        let settings = try #require(h.engine.lastRecorder?.settings)
        #expect(settings.dwell == 0.9)
        #expect(settings.cooldown == 0.45)
        #expect(settings.enterMargin == 0.15)
    }

    @Test func changingThePauseResetsTheDeciderAndTheLoopAtOnce() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        await h.settlePoll()
        h.engine.script.set { _, _ in
            Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0.5))
        }
        h.run(frames: 2, dt: 0.1)
        #expect(h.model.previewDecision != nil)
        #expect(h.model.lookSummary != .off)
        let before = h.engine.recorders.count

        h.model.setCooldown(1.2)

        #expect(h.engine.recorders.count == before + 1, "A new decider, so a cooldown in progress ends")
        #expect(h.model.previewDecision == nil)
        #expect(h.model.lookSummary == .off)
        #expect(h.model.loop.polled == nil)
    }

    @Test func theInstantButtonSetsTheShortHoldAndPauseAndKeepsTheConfidence() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.setSwitchConfidence(4)
        h.model.setHoldTime(1.0)
        h.model.setCooldown(1.0)
        let recorders = h.engine.recorders.count

        h.model.useInstantTiming()

        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.10, cooldown: 0.30, confidenceLevel: 4))
        let settings = try #require(h.engine.lastRecorder?.settings)
        #expect(h.engine.recorders.count == recorders + 1)
        #expect(settings.dwell == 0.10)
        #expect(settings.cooldown == 0.30)
        #expect(settings.enterMargin == 0.45)
        #expect(h.relaunchedModel().sensitivity == SwitchSensitivity(dwell: 0.10, cooldown: 0.30, confidenceLevel: 4))
    }

    @Test func theInstantButtonFromTheDefaultsIsThePreset() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.useInstantTiming()

        #expect(h.model.sensitivity == .instant)
    }

    @Test func theInstantButtonAgainRebuildsNothing() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.useInstantTiming()
        let recorders = h.engine.recorders.count

        h.model.useInstantTiming()

        #expect(h.engine.recorders.count == recorders)
    }

    @Test func draggingTheSlidersToTheInstantValuesGivesTheSameSettingsAsTheButton() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.setHoldTime(0.1)
        h.model.setCooldown(0.3)

        #expect(h.model.sensitivity == .instant)
        #expect(h.model.sensitivity == h.model.sensitivity.applyingInstantTiming())
    }

    @Test func changingTheTimingDoesNotMakeTheSettingsChangeAtTheFrameRate() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        await h.settlePoll()
        h.model.useInstantTiming()
        let count = OSAllocatedUnfairLock(initialState: 0)

        withObservationTracking {
            _ = h.model.sensitivity
        } onChange: {
            count.withLock { $0 += 1 }
        }
        h.run(frames: 30, dt: 0.07)

        #expect(count.withLock { $0 } == 0, "Only the user's own change touches the settings")
    }

    @Test func settingTheSameValueRebuildsNothing() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let recorders = h.engine.recorders.count

        h.model.setHoldTime(0.4)
        h.model.setSwitchConfidence(2)

        #expect(h.engine.recorders.count == recorders)
        #expect(h.defaults.data(forKey: "sway.switchSensitivity") == nil)
    }

    @Test func restoreDefaultsPutsAllThreeBackAndRebuildsTheDecider() throws {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.setHoldTime(1.2)
        h.model.setCooldown(0.5)
        h.model.setSwitchConfidence(4)
        let recorders = h.engine.recorders.count

        h.model.restoreSensitivityDefaults()

        #expect(h.model.sensitivity == .default)
        #expect(h.engine.recorders.count == recorders + 1)
        #expect(h.engine.lastRecorder?.settings == .default)
        #expect(h.relaunchedModel().sensitivity == .default)
    }

    @Test func restoreDefaultsUndoesTheInstantButton() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.useInstantTiming()

        h.model.restoreSensitivityDefaults()

        #expect(h.model.sensitivity == SwitchSensitivity(dwell: 0.40, cooldown: 0.75, confidenceLevel: 2))
        #expect(h.engine.lastRecorder?.settings == .default)
    }

    // MARK: Login item

    @Test func theToggleReadsTheLoginItemWhenTheWindowAppears() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.loginItem.status = .enabled

        #expect(!h.model.opensAtLogin, "Not read until the window appears")
        h.openSettings()

        #expect(h.model.loginItemStatus == .enabled)
        #expect(h.model.opensAtLogin)
    }

    @Test func aWindowNobodyAskedForDoesNotReadTheLoginItem() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.loginItem.status = .enabled

        h.model.settingsWindowDidAppear()

        #expect(h.model.loginItemStatus == .disabled)
        #expect(!h.model.settingsVisible)
    }

    @Test func eachLoginItemStateGivesTheRightToggle() {
        let cases: [(LoginItemStatus, Bool)] = [
            (.enabled, true), (.requiresApproval, true), (.disabled, false), (.unavailable("No."), false),
        ]
        for (status, isOn) in cases {
            let h = Harness.make()
            defer { h.tearDown() }
            h.loginItem.status = status
            h.openSettings()
            #expect(h.model.opensAtLogin == isOn, "\(status)")
        }
    }

    @Test func turningTheToggleOnAndOffRegistersAndUnregisters() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()

        h.model.setOpensAtLogin(true)
        #expect(h.loginItem.setEnabledCalls == [true])
        #expect(h.model.loginItemStatus == .enabled)
        #expect(h.model.opensAtLogin)

        h.model.setOpensAtLogin(false)
        #expect(h.loginItem.setEnabledCalls == [true, false])
        #expect(h.model.loginItemStatus == .disabled)
        #expect(!h.model.opensAtLogin)
        #expect(h.model.loginItemMessage == nil)
    }

    @Test func approvalIsStillPendingWhenTheSystemAsksForIt() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()
        h.loginItem.status = .requiresApproval

        h.model.refreshLoginItemStatus()
        h.model.openLoginItemsSettings()

        #expect(h.model.loginItemStatus == .requiresApproval)
        #expect(h.model.opensAtLogin)
        #expect(h.loginItem.openSettingsCount == 1)
    }

    @Test func aLoginItemErrorShowsItsMessageAndLeavesTheToggleAsTheSystemHasIt() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()
        h.loginItem.error = LoginItemError(message: "Sway could not be set to open at login: nope.")

        h.model.setOpensAtLogin(true)

        #expect(h.model.loginItemMessage == "Sway could not be set to open at login: nope.")
        #expect(h.model.loginItemStatus == .disabled)
        #expect(!h.model.opensAtLogin)

        h.loginItem.error = nil
        h.model.setOpensAtLogin(true)
        #expect(h.model.loginItemMessage == nil, "A new attempt clears the old message")
        #expect(h.model.opensAtLogin)
    }

    @Test func returningToTheAppRereadsTheLoginItemWhileSettingsIsOpen() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()
        h.loginItem.status = .requiresApproval

        h.notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(h.model.loginItemStatus == .requiresApproval)

        h.model.settingsWindowDidDisappear()
        h.loginItem.status = .enabled
        h.notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(h.model.loginItemStatus == .requiresApproval, "Not read while the window is closed")
    }

    // MARK: Shortcut recorder

    @Test func recordingListensOnlyWhileItRecordsAndUnregistersTheCurrentShortcut() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(!h.keyMonitor.isActive)

        h.model.beginShortcutRecording()

        #expect(h.model.isRecordingShortcut)
        #expect(h.keyMonitor.isActive)
        #expect(h.hotKeys.registered[.toggleFocusLock] == nil, "Pressing it again must not toggle Focus Lock")

        pressOptionCommandK(h)

        #expect(!h.model.isRecordingShortcut)
        #expect(!h.keyMonitor.isActive)
        #expect(h.keyMonitor.startCount == 1)
        #expect(h.keyMonitor.stopCount == 1)
    }

    @Test func aRecordedShortcutIsRegisteredSavedAndUsedByTheNextLaunch() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.beginShortcutRecording()
        pressOptionCommandK(h)

        #expect(h.model.focusLockShortcut == optionCommandK)
        #expect(h.hotKeys.registered[.toggleFocusLock] == optionCommandK)
        #expect(h.model.shortcutMessage == nil)
        #expect(h.defaults.data(forKey: shortcutKey) != nil)
        let hotKeys = FakeHotKeys()
        let relaunched = h.relaunchedModel(hotKeys: hotKeys)
        #expect(relaunched.focusLockShortcut == optionCommandK)
        #expect(hotKeys.registered[.toggleFocusLock] == optionCommandK)

        h.hotKeys.press()
        #expect(h.model.focusLocked, "The new shortcut works")
    }

    @Test func everyPressIsConsumedWhileRecordingAndNoneAfter() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.beginShortcutRecording()

        #expect(h.keyMonitor.press(13, [.command], characters: "w"), "A recorded press never closes a window")
        #expect(!h.model.isRecordingShortcut)
        #expect(!h.keyMonitor.press(13, [.command], characters: "w"), "Nothing listens once it is over")
    }

    @Test func escapeCancelsAndTheOldShortcutIsRegisteredAgain() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.beginShortcutRecording()
        #expect(h.hotKeys.registered[.toggleFocusLock] == nil)

        h.keyMonitor.press(53)

        #expect(!h.model.isRecordingShortcut)
        #expect(!h.keyMonitor.isActive)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(h.model.focusLockShortcut == .focusLockDefault)
        #expect(h.defaults.data(forKey: shortcutKey) == nil, "Nothing was saved")
    }

    @Test func theCancelButtonAndTheWindowClosingAlsoCancel() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()

        h.model.beginShortcutRecording()
        h.model.cancelShortcutRecording()
        #expect(!h.keyMonitor.isActive)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)

        h.model.beginShortcutRecording()
        h.model.settingsWindowDidDisappear()
        #expect(!h.model.isRecordingShortcut)
        #expect(!h.keyMonitor.isActive)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
    }

    @Test func cancellingWithNoShortcutLeavesNoneRegistered() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.clearFocusLockShortcut()
        h.model.beginShortcutRecording()

        h.model.cancelShortcutRecording()

        #expect(h.hotKeys.registered[.toggleFocusLock] == nil)
        #expect(h.model.focusLockShortcut == nil)
    }

    @Test func quittingWhileRecordingStopsTheMonitor() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.beginShortcutRecording()

        await h.model.shutdown()

        #expect(!h.keyMonitor.isActive)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
    }

    @Test func aPressWithoutAnActionModifierKeepsRecordingAndExplains() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.beginShortcutRecording()

        h.keyMonitor.press(0, [], characters: "a")
        #expect(h.model.isRecordingShortcut)
        #expect(h.model.shortcutRecordingHint == "Use Control, Option, or Command with a key.")
        h.keyMonitor.press(0, [.shift], characters: "A")
        #expect(h.model.isRecordingShortcut)

        pressOptionCommandK(h)
        #expect(!h.model.isRecordingShortcut)
        #expect(h.model.shortcutRecordingHint == nil)
        #expect(h.model.focusLockShortcut == optionCommandK)
    }

    @Test func aShortcutAnotherAppUsesIsRefusedAndThePreviousOneStays() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(optionCommandK, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        h.model.beginShortcutRecording()

        pressOptionCommandK(h)

        #expect(h.model.focusLockShortcut == .focusLockDefault)
        #expect(hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(
            h.model.shortcutMessage
                == "\u{2325}\u{2318}K is already used by another app. Choose another shortcut in Settings.")
        #expect(h.defaults.data(forKey: shortcutKey) == nil)
        #expect(!h.model.isRecordingShortcut)
        #expect(!h.keyMonitor.isActive)
    }

    @Test func aLaterSuccessClearsTheFailureMessage() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(optionCommandK, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        h.model.beginShortcutRecording()
        pressOptionCommandK(h)
        #expect(h.model.shortcutMessage != nil)

        h.model.beginShortcutRecording()
        h.keyMonitor.press(37, [.control, .option], characters: "l")

        #expect(h.model.shortcutMessage == nil)
        #expect(h.model.focusLockShortcut?.displayString == "\u{2303}\u{2325}L")
    }

    @Test func clearRemovesTheShortcutAndResetRestoresTheDefault() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.clearFocusLockShortcut()
        #expect(h.model.focusLockShortcut == nil)
        #expect(h.hotKeys.registered[.toggleFocusLock] == nil)
        #expect(h.defaults.data(forKey: shortcutKey) == Data())
        #expect(h.relaunchedModel().focusLockShortcut == nil)

        h.model.resetFocusLockShortcut()
        #expect(h.model.focusLockShortcut == .focusLockDefault)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(h.relaunchedModel().focusLockShortcut == .focusLockDefault)
    }

    @Test func resetFailingKeepsWhatWasThere() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(.focusLockDefault, .registrationFailed(-9878))]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        h.model.beginShortcutRecording()
        pressOptionCommandK(h)
        #expect(h.model.focusLockShortcut == optionCommandK)

        h.model.resetFocusLockShortcut()

        #expect(h.model.focusLockShortcut == optionCommandK)
        #expect(hotKeys.registered[.toggleFocusLock] == optionCommandK)
        #expect(h.model.shortcutMessage == "The Focus Lock shortcut could not be set up.")
    }

    @Test func aKeyPressOutsideRecordingIsLeftAlone() {
        let h = Harness.make()
        defer { h.tearDown() }

        #expect(
            !h.model.handleRecordedKey(
                ShortcutKeyPress(keyCode: 40, modifierFlags: [.command], charactersIgnoringModifiers: "k")))
    }

    @Test func startingToRecordTwiceInstallsOneMonitor() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.beginShortcutRecording()
        h.model.beginShortcutRecording()

        #expect(h.keyMonitor.startCount == 1)
        #expect(h.hotKeys.unregisterCalls.count == 1)
    }

    // MARK: Saved calibrations

    private func threeCalibrations(_ h: (UserDefaults) -> Void = { _ in }) -> Harness {
        // Newest first: Left and Right on the built-in camera, then on the external one, then an old pair.
        let old = Fixtures.profile(
            layout: DisplayLayout(displays: [Fixtures.left, Fixtures.far]), cameraName: Fixtures.builtInCamera.name,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000))
        let external = Fixtures.profile(
            cameraName: Fixtures.externalCamera.name, createdAt: Date(timeIntervalSince1970: 1_650_000_000))
        let current = Fixtures.profile(createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return Harness.make(
            seed: { Harness.seedLibrary([current, external, old], into: $0) })
    }

    @Test func theListHasOneRowPerProfileNewestFirstWithTheOneInUseMarked() {
        let h = threeCalibrations()
        defer { h.tearDown() }

        let rows = h.model.calibrationRows

        #expect(rows.count == 3)
        #expect(rows.map(\.camera) == ["FaceTime HD Camera", "Logitech C922", "FaceTime HD Camera"])
        #expect(
            rows.map(\.date) == [1_700_000_000, 1_650_000_000, 1_600_000_000].map(Date.init(timeIntervalSince1970:)))
        #expect(rows.map(\.isInUse) == [true, false, false])
        #expect(rows.first?.key == Fixtures.profile().key)
    }

    @Test func theRowsNameTheirDisplaysFromTheCurrentLayoutElseUnknown() {
        let h = threeCalibrations()
        defer { h.tearDown() }

        let rows = h.model.calibrationRows

        #expect(rows[0].displays == "Left, Right")
        #expect(rows[2].displays == "Left, Unknown display", "Far is not connected")
    }

    @Test func aDisplayNamedInTheLatestAnalysisIsNamedEvenWhenDisconnected() {
        let h = threeCalibrations()
        defer { h.tearDown() }
        h.model.adopt(
            GateAnalysis(
                reports: [
                    SeparabilityReport(
                        featureSet: .visionAngles,
                        displays: [
                            DisplayPoseStats(
                                displayID: Fixtures.far.id, displayName: "Studio Display", frameCount: 10,
                                faceCount: 10, meanX: 0, meanY: 0, stdX: 1, stdY: 1)
                        ], pairs: [], accuracy: nil, verdict: .go, notes: [])
                ], overall: .go, bestFeatureSet: .visionAngles, thresholds: .default),
            trace: Fixtures.trace(), source: .gateTest)

        #expect(h.model.calibrationRows[2].displays == "Left, Studio Display")
    }

    @Test func noCalibrationsGivesNoRows() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.calibrationRows.isEmpty)
    }

    @Test func anAbsentCameraNameReadsAsUnknown() {
        let nameless = Fixtures.profile(cameraName: nil)
        let rows = CalibrationListPresentation.rows(
            library: CalibrationLibrary(profiles: [nameless]), activeKey: nil, name: { $0.rawValue })

        #expect(rows.first?.camera == "Unknown camera")
        #expect(rows.first?.displays == "display-left, display-right")
        #expect(rows.first?.isInUse == false)
    }

    @Test func deletingTheOneInUseRemovesItAndTrackingHasNoCalibration() async {
        let h = threeCalibrations()
        defer { h.tearDown() }
        let key = Fixtures.profile().key
        #expect(h.model.activeCalibration != nil)

        h.model.deleteCalibration(key)

        #expect(h.model.library.profiles.count == 2)
        #expect(h.model.calibrationRows.map(\.isInUse) == [false, false])
        #expect(h.model.activeCalibration == nil)
        #expect(h.storedLibrary()?.profiles.count == 2)
        #expect(!h.model.library.profiles.contains { $0.key == key })
    }

    @Test func deletingAnotherRowKeepsTheActiveCalibration() {
        let h = threeCalibrations()
        defer { h.tearDown() }
        let external = Fixtures.profile(cameraName: Fixtures.externalCamera.name).key

        h.model.deleteCalibration(external)

        #expect(h.model.library.profiles.count == 2)
        #expect(h.model.activeCalibration?.saved.key == Fixtures.profile().key)
        #expect(h.model.calibrationRows.map(\.isInUse) == [true, false])
    }

    @Test func deletingTheActiveCalibrationWhileTrackingStopsTheCamera() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.model.deleteCalibration(Fixtures.profile().key)
        await h.model.cameraOperation?.value

        #expect(!h.model.isCameraActive)
        #expect(h.model.trackingStatus == .needsCalibration)
    }

    @Test func calibratingAgainBringsADeletedCalibrationBack() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.model.deleteCalibration(Fixtures.profile().key)
        #expect(h.model.calibrationRows.isEmpty)

        await h.openSetupOnCameraCheck()
        await h.completeCalibration()

        #expect(h.model.calibrationRows.map(\.isInUse) == [true])
        #expect(h.model.activeCalibration != nil)
    }

    @Test func deletingAKeyThatIsNotThereChangesNothing() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        let before = h.model.library

        h.model.deleteCalibration(CalibrationKey(displayIDs: [Fixtures.far.id, Fixtures.left.id], cameraName: "x"))

        #expect(h.model.library == before)
    }
}
