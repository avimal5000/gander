import AppKit
import CoreGraphics
import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("Edge glow and Focus Lock notice")
struct AppModelFeedbackTests {
    private let left = Fixtures.left
    private let right = Fixtures.right

    /// A calibrated model with Tracking on and the camera running.
    private func trackingHarness(layout: DisplayLayout = Fixtures.twoDisplays) async -> Harness {
        let h = Harness.make(layout: layout, calibrated: true)
        await h.startTracking()
        await h.settlePoll()
        return h
    }

    /// Makes the scripted decider ask for `target` from the first sample on.
    private func scriptSwitch(_ h: Harness, to target: DisplayInfo) {
        h.engine.script.set { sample, _ in
            Fixtures.decision(
                switchTo: target.id, phase: .coolingDown(until: sample.timestamp + 0.75),
                classification: Fixtures.classification(best: target.id))
        }
    }

    private func focused(on display: DisplayInfo) -> FocusResult {
        .focused(Fixtures.window(7, on: display), method: .accessibilityRaise, milliseconds: 100)
    }

    /// Runs one tracking switch to `target` that ends with `result`.
    private func switchOnce(_ h: Harness, to target: DisplayInfo, result: FocusResult) async {
        h.focus.setResult(result)
        scriptSwitch(h, to: target)
        h.model.handle(.sample(Fixtures.sample(at: 1)))
        await h.settleSwitch()
    }

    // MARK: Glow

    @Test func aTrackingSwitchThatFocusedAWindowShowsOneGlowOnThatDisplay() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        await switchOnce(h, to: right, result: focused(on: right))

        #expect(h.focus.focusCalls == [right.id])
        #expect(h.feedback.glows == [FakeFeedback.Glow(display: right, animated: true)])
        #expect(h.feedback.notices.isEmpty)
    }

    @Test func theGlowIsOnTheTargetDisplayWhicheverItIs() async {
        let h = await trackingHarness(layout: Fixtures.threeDisplays)
        defer { h.tearDown() }

        await switchOnce(h, to: Fixtures.far, result: focused(on: Fixtures.far))

        #expect(h.feedback.glows.map(\.display) == [Fixtures.far])
    }

    @Test func noGlowWhenNoWindowWasFocused() async {
        let results: [FocusResult] = [
            .noWindow(right.id),
            .failed(Fixtures.window(7, on: right), reason: "The window did not take focus"),
            .notTrusted,
        ]
        for result in results {
            let h = await trackingHarness()
            defer { h.tearDown() }

            await switchOnce(h, to: right, result: result)

            #expect(h.focus.focusCalls == [right.id], "\(result)")
            #expect(h.feedback.glows.isEmpty, "\(result)")
        }
    }

    @Test func noGlowWhileTheSettingIsOffAndTheNextOneWorksAfterTurningItOn() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.model.setEdgeGlowEnabled(false)

        await switchOnce(h, to: right, result: focused(on: right))
        #expect(h.feedback.glows.isEmpty)

        h.model.setEdgeGlowEnabled(true)
        h.model.resetTracking()
        await switchOnce(h, to: left, result: focused(on: left))
        #expect(h.feedback.glows.map(\.display) == [left])
    }

    @Test func theGlowDoesNotAnimateWithReduceMotion() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.appState.reduceMotion = true

        await switchOnce(h, to: right, result: focused(on: right))

        #expect(h.feedback.glows == [FakeFeedback.Glow(display: right, animated: false)])
    }

    @Test func reduceMotionIsReadEachTimeNotAtLaunch() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        await switchOnce(h, to: right, result: focused(on: right))
        h.appState.reduceMotion = true
        h.model.resetTracking()
        await switchOnce(h, to: left, result: focused(on: left))

        #expect(h.feedback.glows.map(\.animated) == [true, false])
    }

    @Test func aFocusTestRequestNeverShowsTheGlow() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.focus.setResult(focused(on: right))
        h.model.noteWindowRequested(SwayWindowID.focusTest)
        h.model.startFocusTest()
        await h.model.focusPollTask?.value

        h.model.focusNow(right.id)
        await h.model.focusRequestTask?.value

        #expect(h.focus.focusCalls == [right.id], "The request ran")
        #expect(h.model.focusLog.first?.text.contains("Focused") == true)
        #expect(h.feedback.glows.isEmpty)
        h.model.stopFocusTest()
    }

    @Test func aLateResultFromBeforeAResetShowsNoGlow() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focused(on: right))
        h.focus.holdFocusRequests()
        scriptSwitch(h, to: right)
        h.model.handle(.sample(Fixtures.sample(at: 1)))
        _ = await waitUntil { h.focus.isHoldingFocus }

        h.model.resetTracking()
        h.focus.release()
        await h.model.focusSwitchTask?.value

        #expect(h.feedback.glows.isEmpty, "Tracking was reset: the result is ignored")
    }

    @Test func aGlowForADisplayThatIsGoneShowsNothing() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.showEdgeGlow(on: "display-unplugged")

        #expect(h.feedback.glows.isEmpty)
    }

    // MARK: Notice

    @Test func theShortcutShowsFocusLockOnThenOffOnTheMainDisplayWhenFocusIsUnknown() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.loop.focusedDisplay == nil)

        h.hotKeys.press()
        h.hotKeys.press()

        #expect(
            h.feedback.notices == [
                FakeFeedback.Notice(text: "Focus Lock on", symbol: "lock.fill", display: left, animated: true),
                FakeFeedback.Notice(text: "Focus Lock off", symbol: "lock.open", display: left, animated: true),
            ])
        #expect(!h.model.focusLocked)
    }

    @Test func theNoticeShowsOnTheDisplayThatHoldsFocus() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(right.id)
        await h.startTracking()
        await h.settlePoll()
        #expect(h.model.loop.focusedDisplay == right.id)

        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.display) == [right])
        #expect(h.model.focusLocked)
    }

    @Test func theNoticeFallsBackToTheMenuBarDisplayWhenFocusIsOnADisplayThatIsGone() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.focus.setFocusedDisplay("display-unplugged")
        await h.startTracking()
        await h.settlePoll()

        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.display) == [left], "The layout's main display")
    }

    @Test func theMenuSwitchShowsNoNotice() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.setFocusLock(true)
        h.model.setFocusLock(false)
        h.model.toggleFocusLock()

        #expect(h.feedback.notices.isEmpty)
    }

    @Test func noNoticeWhileTheSettingIsOffButTheLockStillToggles() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.setFocusLockNoticeEnabled(false)

        h.hotKeys.press()

        #expect(h.model.focusLocked)
        #expect(h.feedback.notices.isEmpty)

        h.model.setFocusLockNoticeEnabled(true)
        h.hotKeys.press()
        #expect(h.feedback.notices.map(\.text) == ["Focus Lock off"])
    }

    @Test func theNoticeDoesNotAnimateWithReduceMotion() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.appState.reduceMotion = true

        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.animated) == [false])
    }

    @Test func aNewShortcutShowsTheNoticeToo() {
        let h = Harness.make()
        defer { h.tearDown() }
        let other = HotKeyShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        #expect(h.model.setFocusLockShortcut(other))

        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.text) == ["Focus Lock on"])
    }

    @Test func theShortcutRegisteredAgainAfterACancelledRecordingShowsTheNoticeToo() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSettings()
        h.model.beginShortcutRecording()
        h.model.cancelShortcutRecording()

        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.text) == ["Focus Lock on"])
    }

    @Test func aRefusedShortcutKeepsThePreviousOneWorkingWithItsNotice() {
        let hotKeys = FakeHotKeys()
        let refused = HotKeyShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
        hotKeys.failures = [(refused, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }

        #expect(!h.model.setFocusLockShortcut(refused))
        h.hotKeys.press()

        #expect(h.feedback.notices.map(\.text) == ["Focus Lock on"], "The previous shortcut, registered again")
    }

    @Test func noNoticeWithoutAnyDisplay() {
        let h = Harness.make(layout: .empty)
        defer { h.tearDown() }

        h.hotKeys.press()

        #expect(h.model.focusLocked)
        #expect(h.feedback.notices.isEmpty)
    }

    @Test func theNoticeWordsAndSymbols() {
        #expect(FocusLockNotice(isOn: true).text == "Focus Lock on")
        #expect(FocusLockNotice(isOn: true).symbol == "lock.fill")
        #expect(FocusLockNotice(isOn: false).text == "Focus Lock off")
        #expect(FocusLockNotice(isOn: false).symbol == "lock.open")
        for isOn in [true, false] {
            let symbol = FocusLockNotice(isOn: isOn).symbol
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) must exist")
        }
    }

    // MARK: Timing and layout

    @Test func theGlowTimingsAreTheContractOnes() {
        let timing = FeedbackTiming.glow
        #expect(timing.fadeIn == 0.1)
        #expect(timing.hold == 0.05)
        #expect(timing.fadeOut == 0.2)
        #expect(abs(timing.totalDuration(animated: true) - 0.35) < 1e-9)
        #expect(timing.totalDuration(animated: false) == 0.35)
    }

    @Test func theNoticeTimingsAreTheContractOnes() {
        let timing = FeedbackTiming.notice
        #expect(timing.fadeIn == 0.15)
        #expect(timing.hold == 1)
        #expect(timing.fadeOut == 0.3)
        #expect(timing.totalDuration(animated: false) == 1.3)
    }

    @Test func theNoticeIsCenteredFortyEightPointsBelowTheTopOfTheVisibleFrame() {
        // A 1920 x 1080 screen with a 25 pt menu bar: the visible frame ends 25 pt short of the top.
        let visible = CGRect(x: 100, y: 0, width: 1920, height: 1055)
        let frame = FeedbackLayout.noticeFrame(size: CGSize(width: 181, height: 36), in: visible)

        #expect(frame.size == CGSize(width: 181, height: 36))
        #expect(abs(frame.midX - visible.midX) <= 0.5)
        #expect(frame.maxY == visible.maxY - 48, "The top of the pill, 48 pt below the top of the visible frame")
        #expect(frame.origin.x == frame.origin.x.rounded() && frame.origin.y == frame.origin.y.rounded())
    }

    @Test func theGlowIsFourPointsOfBorderWithATenPointFalloffAtFortyPercent() {
        #expect(EdgeGlowView.borderWidth == 4)
        #expect(EdgeGlowView.glowWidth == 10)
        #expect(EdgeGlowView.glowOpacity == 0.4)
        let rings = (0..<Int(EdgeGlowView.glowWidth)).map { EdgeGlowView.ringOpacity(at: $0) }
        #expect(rings.first.map { $0 <= 0.4 && $0 > 0.3 } == true)
        #expect(rings.last.map { $0 < 0.01 } == true)
        #expect(zip(rings, rings.dropFirst()).allSatisfy { $0 > $1 }, "Fading outward")
    }

    // MARK: The live controller

    @Test func theLiveControllerCreatesNoPanelUntilItShowsSomething() {
        // No screen for any display: the test never touches a real screen or shows a panel.
        let controller = FeedbackOverlayController(screenFor: { _ in nil })
        #expect(!controller.hasPanels)

        controller.showGlow(on: Fixtures.left, animated: false)
        controller.showNotice("Focus Lock on", symbol: "lock.fill", on: Fixtures.left, animated: false)

        #expect(!controller.hasPanels, "Nothing to draw on, so nothing is created")
    }
}
