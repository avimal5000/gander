import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel focus test")
struct AppModelFocusTestTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id

    /// A harness with the Focus Test window open (as the menu would open it) and its first refresh applied.
    private func openWindow(trusted: Bool = true) async -> Harness {
        let h = Harness.make(trusted: trusted)
        h.focus.setWindows([left: Fixtures.window(1, app: "Safari", title: "Secret page", on: Fixtures.left)])
        h.model.noteWindowRequested(SwayWindowID.focusTest)
        h.model.startFocusTest()
        await settle(h)
        return h
    }

    /// Waits for the refresh and focus request in flight, if any.
    private func settle(_ h: Harness) async {
        let poll = h.model.focusPollTask
        await poll?.value
        let request = h.model.focusRequestTask
        await request?.value
    }

    /// Moves the model clock and ticks, as the timer would.
    private func tick(_ h: Harness, after seconds: TimeInterval) async {
        h.clock.advance(by: seconds)
        h.model.focusTick()
        await settle(h)
    }

    // MARK: Result texts

    @Test func resultsReadAsPlainSentences() {
        let window = Fixtures.window(7, app: "Safari", title: "Hidden")
        let name: (DisplayID) -> String = { $0 == Fixtures.left.id ? "Left" : "?" }
        func text(_ result: FocusResult) -> String { FocusTestPresentation.logText(for: result, displayName: name) }

        #expect(
            text(.focused(window, method: .appActivation, milliseconds: 42))
                == "Focused Safari via app activation in 42 ms")
        #expect(
            text(.focused(window, method: .accessibilityFrontmost, milliseconds: 310))
                == "Focused Safari via Accessibility frontmost in 310 ms")
        #expect(text(.noWindow(Fixtures.left.id)) == "No window on Left")
        #expect(text(.notTrusted) == "Accessibility permission needed")
        #expect(text(.failed(window, reason: "Focus did not move to Safari")) == "Failed: Focus did not move to Safari")
        #expect(text(.failed(nil, reason: "Window not found through Accessibility")).hasPrefix("Failed: Window"))
    }

    @Test func windowTextShowsAppAndTitleOrJustTheApp() {
        #expect(
            FocusTestPresentation.windowText(Fixtures.window(1, app: "Safari", title: "Docs")) == "Safari \u{2014} Docs"
        )
        #expect(FocusTestPresentation.windowText(Fixtures.window(1, app: "Safari", title: nil)) == "Safari")
        #expect(FocusTestPresentation.windowText(Fixtures.window(1, app: "Safari", title: "")) == "Safari")
        #expect(FocusTestPresentation.windowText(nil) == "No window")
    }

    @Test func rowsFollowTheLayoutOrderAndMarkTheFocusedDisplay() {
        let rows = FocusTestPresentation.rows(
            layout: Fixtures.threeDisplays,
            windows: [Fixtures.left.id: Fixtures.window(1, app: "Safari", title: "Docs", on: Fixtures.left)],
            focused: Fixtures.right.id)

        #expect(rows.map(\.title) == ["Left", "Right (focused)", "Far"])
        #expect(rows.map(\.windowText) == ["Safari \u{2014} Docs", "No window", "No window"])
        #expect(rows.map(\.hasWindow) == [true, false, false])
        #expect(rows.map(\.isFocused) == [false, true, false])
    }

    @Test func identicalDisplayNamesGetNumbers() {
        let twin = DisplayInfo(
            id: "display-twin", cgDisplayID: 20, name: "Left", frame: CGRect(x: 6400, y: 0, width: 1920, height: 1080),
            isBuiltIn: false, isMain: false)
        let rows = FocusTestPresentation.rows(
            layout: DisplayLayout(displays: [Fixtures.left, twin]), windows: [:], focused: nil)
        #expect(rows.map(\.title) == ["Left (1)", "Left (2)"])
    }

    // MARK: Opening and polling

    @Test func openingTheWindowShowsTheLastUsedWindowsAndTheFocusedDisplay() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.focus.setWindows([left: Fixtures.window(1)])
        h.focus.setFocusedDisplay(right)
        h.model.noteWindowRequested(SwayWindowID.focusTest)

        h.model.startFocusTest()
        await settle(h)

        #expect(h.model.focusWindows == [left: Fixtures.window(1)])
        #expect(h.model.focusedDisplayID == right)
        #expect(h.model.isAccessibilityTrusted)
        #expect(h.focus.lastUsedWindowsCalls == 1)
        #expect(h.focus.focusedDisplayCalls == 1)
    }

    @Test func aWindowNobodyAskedForNeverStartsPolling() async {
        // SwiftUI opens every Window scene at launch; the launch guard closes the unrequested one unseen.
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.startFocusTest()
        await tick(h, after: 5)

        #expect(h.focus.isTrustedCalls == 0)
        #expect(h.focus.lastUsedWindowsCalls == 0)
    }

    @Test func theTrustAndWindowPollRunsOnlyWhileTheWindowIsVisible() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.noteWindowRequested(SwayWindowID.focusTest)

        await tick(h, after: 1)
        #expect(h.focus.isTrustedCalls == 0, "Not open yet")

        h.model.startFocusTest()
        await settle(h)
        #expect(h.focus.isTrustedCalls == 1)
        #expect(h.focus.lastUsedWindowsCalls == 1)

        await tick(h, after: 0.5)
        #expect(h.focus.isTrustedCalls == 1, "Less than a second has passed")
        await tick(h, after: 0.5)
        #expect(h.focus.isTrustedCalls == 2)
        await tick(h, after: 1)
        #expect(h.focus.isTrustedCalls == 3)
        #expect(h.focus.lastUsedWindowsCalls == 3)
        #expect(h.focus.focusedDisplayCalls == 3)

        h.model.stopFocusTest()
        await tick(h, after: 5)
        await tick(h, after: 5)
        #expect(h.focus.isTrustedCalls == 3)
        #expect(h.focus.lastUsedWindowsCalls == 3)
    }

    @Test func grantingAccessInSystemSettingsShowsUpOnTheNextPoll() async {
        let h = await openWindow(trusted: false)
        defer { h.tearDown() }
        #expect(!h.model.isAccessibilityTrusted)
        #expect(!h.model.canRequestFocus)

        h.focus.setTrusted(true)
        await tick(h, after: 1)

        #expect(h.model.isAccessibilityTrusted)
        #expect(h.model.canRequestFocus)
    }

    @Test func closingTheWindowForgetsTheWindowTitles() async {
        let h = await openWindow()
        defer { h.tearDown() }
        #expect(!h.model.focusWindows.isEmpty)

        h.model.stopFocusTest()

        #expect(h.model.focusWindows.isEmpty)
        #expect(h.model.focusedDisplayID == nil)
    }

    @Test func aRefreshThatFinishesAfterTheWindowClosedIsDropped() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.focus.setWindows([left: Fixtures.window(1)])
        h.model.noteWindowRequested(SwayWindowID.focusTest)

        h.model.startFocusTest()
        let inFlight = h.model.focusPollTask
        h.model.stopFocusTest()
        await inFlight?.value

        #expect(h.model.focusWindows.isEmpty)
    }

    // MARK: Not trusted

    @Test func withoutAccessibilityTheButtonsAreDisabledAndNothingIsAttempted() async {
        let h = await openWindow(trusted: false)
        defer { h.tearDown() }
        #expect(!h.model.canRequestFocus)

        h.model.focusAfterDelay(left)
        #expect(h.model.focusActivity == .idle)

        h.model.focusNow(left)
        await settle(h)

        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.model.focusLog.map(\.text) == ["Accessibility permission needed"])
    }

    @Test func aNotTrustedResultDisablesTheButtonsUntilTheNextPoll() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.focus.setResult(.notTrusted)
        h.focus.setTrusted(false)

        h.model.focusNow(left)
        await settle(h)

        #expect(h.model.focusLog.first?.text == "Accessibility permission needed")
        #expect(!h.model.isAccessibilityTrusted)
        #expect(!h.model.canRequestFocus)
    }

    // MARK: Focus

    @Test func focusAsksTheControllerForTheDisplayAndLogsTheResult() async {
        let h = await openWindow()
        defer { h.tearDown() }
        let window = Fixtures.window(1, app: "Safari", title: "Secret page")
        h.focus.setResult(.focused(window, method: .appActivation, milliseconds: 42))

        h.model.focusNow(left)
        #expect(h.model.focusActivity == .focusing(display: left))
        await settle(h)

        #expect(h.focus.focusCalls == [left])
        #expect(h.model.focusLog.map(\.text) == ["Focused Safari via app activation in 42 ms"])
        #expect(h.model.focusActivity == .idle)
        #expect(h.model.canRequestFocus)
    }

    @Test func everyKindOfResultReachesTheLog() async {
        let h = await openWindow()
        defer { h.tearDown() }
        let window = Fixtures.window(1, app: "Notes", title: "Secret page")
        let results: [FocusResult] = [
            .focused(window, method: .appActivation, milliseconds: 310),
            .noWindow(right),
            .failed(window, reason: "Focus did not move to Notes"),
        ]
        for result in results {
            h.focus.setResult(result)
            h.model.focusNow(left)
            await settle(h)
        }

        #expect(
            h.model.focusLog.map(\.text) == [
                "Failed: Focus did not move to Notes",
                "No window on Right",
                "Focused Notes via app activation in 310 ms",
            ])
    }

    @Test func theLogNeverContainsAWindowTitle() async {
        let h = await openWindow()
        defer { h.tearDown() }
        let window = Fixtures.window(1, app: "Safari", title: "Secret page")
        for result: FocusResult in [
            .focused(window, method: .appActivation, milliseconds: 5),
            .failed(window, reason: "Focus did not move to Safari"),
        ] {
            h.focus.setResult(result)
            h.model.focusNow(left)
            await settle(h)
        }

        #expect(h.model.focusLog.count == 2)
        #expect(h.model.focusLog.allSatisfy { !$0.text.contains("Secret page") })
    }

    @Test func theLogKeepsTheNewestTenFirst() async {
        let h = await openWindow()
        defer { h.tearDown() }
        for index in 0..<12 {
            h.focus.setResult(.failed(nil, reason: "attempt \(index)"))
            h.model.focusNow(left)
            await settle(h)
        }

        #expect(h.model.focusLog.count == AppModel.focusLogLimit)
        #expect(h.model.focusLog.first?.text == "Failed: attempt 11")
        #expect(h.model.focusLog.last?.text == "Failed: attempt 2")
    }

    @Test func onlyOneRequestRunsAtATime() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        h.focus.setResult(.noWindow(left))

        h.model.focusNow(left)
        let held = await waitUntil { h.focus.isHoldingFocus }
        #expect(held)
        #expect(!h.model.canRequestFocus)

        h.model.focusNow(right)
        h.model.focusNow(left)
        h.model.focusAfterDelay(right)
        #expect(h.focus.focusCalls == [left])
        #expect(h.model.focusActivity == .focusing(display: left))

        h.focus.release()
        await settle(h)

        #expect(h.focus.focusCalls == [left])
        #expect(h.model.focusLog.count == 1)
        #expect(h.model.canRequestFocus)

        h.model.focusNow(right)
        await settle(h)
        #expect(h.focus.focusCalls == [left, right])
    }

    // MARK: Focus in 3 s

    @Test func theDelayedFocusFiresAfterThreeSecondsOnTheInjectedClock() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.focus.setResult(.noWindow(left))

        h.model.focusAfterDelay(left)
        #expect(h.model.focusActivity == .countingDown(display: left, deadline: 3))
        #expect(h.model.focusCountdownSeconds == 3)
        #expect(!h.model.canRequestFocus)

        await tick(h, after: 1.25)
        #expect(h.model.focusCountdownSeconds == 2)
        await tick(h, after: 1.25)
        #expect(h.model.focusCountdownSeconds == 1)
        await tick(h, after: 0.25)
        #expect(h.focus.focusCalls.isEmpty, "2.75 s have passed")
        #expect(h.model.focusActivity != .idle)

        await tick(h, after: 0.25)
        #expect(h.focus.focusCalls == [left])
        #expect(h.model.focusLog.map(\.text) == ["No window on Left"])
        #expect(h.model.focusActivity == .idle)
    }

    @Test func aDelayedFocusCanBeCancelled() async {
        let h = await openWindow()
        defer { h.tearDown() }

        h.model.focusAfterDelay(right)
        await tick(h, after: 2)
        h.model.cancelDelayedFocus()
        #expect(h.model.focusActivity == .idle)
        #expect(h.model.canRequestFocus)

        await tick(h, after: 5)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.model.focusLog.isEmpty)
    }

    @Test func cancellingWhenNothingIsPendingChangesNothing() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        h.model.focusNow(left)
        _ = await waitUntil { h.focus.isHoldingFocus }

        h.model.cancelDelayedFocus()

        #expect(h.model.focusActivity == .focusing(display: left))
        h.focus.release()
        await settle(h)
    }

    @Test func closingTheWindowCancelsAPendingCountdown() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.model.focusAfterDelay(left)

        h.model.stopFocusTest()
        await tick(h, after: 10)

        #expect(h.model.focusActivity == .idle)
        #expect(h.focus.focusCalls.isEmpty)
    }

    @Test func closingTheWindowCancelsARequestInFlight() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        h.focus.setResult(.failed(nil, reason: "Cancelled"))
        h.model.focusNow(left)
        let held = await waitUntil { h.focus.isHoldingFocus }
        #expect(held)

        h.model.stopFocusTest()
        h.focus.release()
        await settle(h)

        #expect(h.focus.focusCancelled == [true])
        #expect(h.model.focusActivity == .idle)
        #expect(h.model.canRequestFocus)
    }

    @Test func aRequestInAnOpenWindowIsNotCancelled() async {
        let h = await openWindow()
        defer { h.tearDown() }

        h.model.focusNow(left)
        await settle(h)

        #expect(h.focus.focusCancelled == [false])
    }

    @Test func aCountdownThatEndsWithoutAccessibilityLogsInsteadOfFocusing() async {
        let h = await openWindow()
        defer { h.tearDown() }
        h.model.focusAfterDelay(left)
        h.focus.setTrusted(false)

        await tick(h, after: 1)
        await tick(h, after: 2.5)

        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.model.focusLog.map(\.text) == ["Accessibility permission needed"])
        #expect(h.model.focusActivity == .idle)
    }

    // MARK: Onboarding

    @Test func grantAccessAsksForTrustAndOpensTheAccessibilityPane() {
        let h = Harness.make(trusted: false)
        defer { h.tearDown() }

        h.model.grantAccessibility()

        #expect(h.focus.requestTrustCalls == 1)
        #expect(h.system.openedAccessibilitySettingsCount == 1)
        #expect(h.system.openedSettingsCount == 0, "The camera pane is not the Accessibility pane")
        #expect(
            AppKitSystemInteractions.accessibilityPrivacyURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @Test func theOnboardingTextsMatchTheContract() {
        #expect(FocusTestPresentation.accessibilityGranted == "Accessibility: Granted")
        #expect(FocusTestPresentation.accessibilityNotGranted == "Accessibility: Not granted")
        #expect(
            FocusTestPresentation.accessibilityExplanation
                == "Sway needs Accessibility access to move keyboard focus to a window on the display you look at. "
                + "It never moves the cursor and never reads window contents.")
    }
}
