import CoreGraphics
import SwayModels
import Testing

@testable import FocusControl

@Suite struct FocusSequenceTests {
    private let target = WindowSummary(
        id: 7,
        processID: 321,
        appName: "Safari",
        title: nil,
        bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
        displayID: "L"
    )

    /// Fast polling so failures finish in milliseconds.
    private let fast = FocusPolling(interval: .milliseconds(1), timeout: .milliseconds(25))

    private func sequence(_ platform: FakeFocusPlatform) -> FocusSequence<FakeFocusPlatform> {
        FocusSequence(platform: platform, polling: fast)
    }

    @Test func windowNotFoundStopsBeforeAnyAction() async {
        let platform = FakeFocusPlatform(handle: nil, rule: .onCheck(1))
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .windowNotFound)
        #expect(platform.calls == [.prepare])
    }

    @Test func raiseThatWorksNeverActivatesTheApp() async {
        let platform = FakeFocusPlatform(title: "Inbox", rule: .onCheck(1))
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focused(target.settingTitle("Inbox"), .accessibilityRaise))
        #expect(platform.calls == [.prepare, .raise, .check])
    }

    @Test func raiseIsVerifiedByPollingUntilFocusLands() async {
        let platform = FakeFocusPlatform(rule: .onCheck(4))
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focused(target, .accessibilityRaise))
        #expect(platform.calls == [.prepare, .raise, .check, .check, .check, .check])
    }

    @Test func activationIsTheFallbackWhenTheRaiseDoesNotTakeEffect() async {
        let platform = FakeFocusPlatform(rule: .afterActivation)
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focused(target, .appActivation))

        let calls = platform.calls
        #expect(calls.first == .prepare)
        #expect(calls[1] == .raise)
        let activationIndex = calls.firstIndex(of: .activate(321))
        #expect(activationIndex != nil)
        // The raise comes again right after activation, then the same verification.
        let after = activationIndex.map { Array(calls[($0 + 1)...]) }
        #expect(after == [.raise, .check])
        // Before activation, the first method was polled more than once.
        #expect(calls[..<(activationIndex ?? 0)].filter { $0 == .check }.count > 1)
    }

    @Test func failureAfterBothMethodsReportsTheSummary() async {
        let platform = FakeFocusPlatform(title: "Inbox", rule: .never)
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focusDidNotMove(target.settingTitle("Inbox")))

        let calls = platform.calls
        #expect(calls.filter { $0 == .raise }.count == 2)
        #expect(calls.filter { $0 == .activate(321) }.count == 1)
    }

    @Test func eachMethodWaitsAboutTheFullTimeoutBeforeGivingUp() async {
        let polling = FocusPolling(interval: .milliseconds(5), timeout: .milliseconds(60))
        let platform = FakeFocusPlatform(rule: .never)
        let clock = ContinuousClock()
        let started = clock.now
        _ = await FocusSequence(platform: platform, polling: polling).run(target: target)
        let elapsed = started.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(110))
        #expect(elapsed < .milliseconds(900))
    }

    @Test func cancellationEndsTheSequenceWithoutTryingTheNextMethod() async {
        let polling = FocusPolling(interval: .milliseconds(5), timeout: .seconds(5))
        let platform = FakeFocusPlatform(rule: .never)
        let task = Task { await FocusSequence(platform: platform, polling: polling).run(target: target) }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(!platform.calls.contains(.activate(321)))
    }

    @Test func standardPollingIs25MillisecondStepsForUpTo300Milliseconds() {
        #expect(FocusPolling.standard.interval == .milliseconds(25))
        #expect(FocusPolling.standard.timeout == .milliseconds(300))
    }
}

@Suite struct FocusSequenceOutcomeTests {
    private let target = WindowSummary(
        id: 7,
        processID: 321,
        appName: "Safari",
        title: nil,
        bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
        displayID: "L"
    )

    @Test func focusedMapsToTheMethodAndTime() {
        let titled = target.settingTitle("Inbox")
        let result = FocusSequenceOutcome.focused(titled, .appActivation).result(for: target, milliseconds: 42)
        #expect(result == .focused(titled, method: .appActivation, milliseconds: 42))
    }

    @Test func windowNotFoundUsesTheContractReason() {
        let result = FocusSequenceOutcome.windowNotFound.result(for: target, milliseconds: 5)
        #expect(result == .failed(target, reason: "Window not found through Accessibility"))
    }

    @Test func failedFocusNamesTheApp() {
        let result = FocusSequenceOutcome.focusDidNotMove(target).result(for: target, milliseconds: 700)
        #expect(result == .failed(target, reason: "Focus did not move to Safari"))
    }

    @Test func cancellationIsReportedAsFailed() {
        let result = FocusSequenceOutcome.cancelled.result(for: target, milliseconds: 1)
        #expect(result == .failed(target, reason: "Cancelled"))
    }
}

@Suite struct FocusVerificationTests {
    @Test func requiresTheTargetAppToBeFrontmost() {
        #expect(!FocusVerification.isVerified(frontmostProcessID: 1, targetProcessID: 2, focusedWindowMatches: true))
        #expect(!FocusVerification.isVerified(frontmostProcessID: nil, targetProcessID: 2, focusedWindowMatches: true))
    }

    @Test func requiresTheFocusedWindowToBeTheTargetWhenReadable() {
        #expect(FocusVerification.isVerified(frontmostProcessID: 2, targetProcessID: 2, focusedWindowMatches: true))
        #expect(!FocusVerification.isVerified(frontmostProcessID: 2, targetProcessID: 2, focusedWindowMatches: false))
    }

    @Test func acceptsThePIDMatchAloneWhenTheFocusedWindowIsUnreadable() {
        #expect(FocusVerification.isVerified(frontmostProcessID: 2, targetProcessID: 2, focusedWindowMatches: nil))
    }
}

@Suite struct WindowSummaryHelpersTests {
    @Test func summaryFromARecordCopiesItsFields() {
        let record = FocusFixtures.record(
            number: 9,
            processID: 55,
            ownerName: "Terminal",
            bounds: CGRect(x: 1, y: 2, width: 300, height: 200)
        )
        let summary = WindowSummary(record: record, displayID: "R", title: nil)
        #expect(
            summary
                == WindowSummary(
                    id: 9,
                    processID: 55,
                    appName: "Terminal",
                    title: nil,
                    bounds: CGRect(x: 1, y: 2, width: 300, height: 200),
                    displayID: "R"
                )
        )
    }

    @Test func settingANilTitleKeepsTheSummaryUnchanged() {
        let summary = WindowSummary(
            id: 1,
            processID: 2,
            appName: "A",
            title: "Known",
            bounds: .zero,
            displayID: "L"
        )
        #expect(summary.settingTitle(nil) == summary)
        #expect(summary.settingTitle("New").title == "New")
    }

    @Test func wholeMillisecondsRoundsDown() {
        #expect(Duration.milliseconds(42).wholeMilliseconds == 42)
        #expect(Duration.microseconds(42_900).wholeMilliseconds == 42)
        #expect(Duration.seconds(2).wholeMilliseconds == 2000)
        #expect(Duration.zero.wholeMilliseconds == 0)
    }
}
