import CoreGraphics
import GanderModels
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
    /// For tests where focus lands after a few checks: a timeout no runner can hit, so the outcome never depends on
    /// machine speed (a slow CI runner once ran out a 25 ms timeout after two checks).
    private let patient = FocusPolling(interval: .milliseconds(1), timeout: .seconds(30))

    private func sequence(_ platform: FakeFocusPlatform) -> FocusSequence<FakeFocusPlatform> {
        FocusSequence(platform: platform, polling: fast)
    }

    @Test func windowNotFoundStopsBeforeAnyAction() async {
        let platform = FakeFocusPlatform(handle: nil, rule: .onCheck(1))
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .windowNotFound)
        #expect(platform.calls == [.prepare])
    }

    @Test func theWindowIsRaisedThenItsAppActivatedWithoutTheAppWideFrontmostCall() async {
        // The user's report: with the app made frontmost through Accessibility, every Terminal window came forward.
        // Activation brings only the raised window, so the app-wide call is not made when activation works.
        let platform = FakeFocusPlatform(title: "Inbox", rule: .afterActivation)
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focused(target.settingTitle("Inbox"), .appActivation))
        #expect(platform.calls == [.prepare, .raise, .activate(321), .check])
    }

    @Test func activationIsVerifiedByPollingUntilFocusLands() async {
        let platform = FakeFocusPlatform(rule: .onCheck(4))
        let outcome = await FocusSequence(platform: platform, polling: patient).run(target: target)
        #expect(outcome == .focused(target, .appActivation))
        #expect(platform.calls == [.prepare, .raise, .activate(321), .check, .check, .check, .check])
    }

    @Test func theAppWideFrontmostCallIsOnlyTheFallbackForAnAppThatIgnoresActivation() async {
        let platform = FakeFocusPlatform(rule: .afterFrontmost)
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focused(target, .accessibilityFrontmost))

        let calls = platform.calls
        #expect(Array(calls.prefix(3)) == [.prepare, .raise, .activate(321)])
        let frontmostIndex = calls.firstIndex(of: .frontmost)
        #expect(frontmostIndex != nil)
        // The raise comes again right after, then the same verification.
        let after = frontmostIndex.map { Array(calls[($0 + 1)...]) }
        #expect(after == [.raise, .check])
        // Before the fallback, activation was polled more than once.
        #expect(calls[..<(frontmostIndex ?? 0)].filter { $0 == .check }.count > 1)
    }

    @Test func failureAfterBothMethodsReportsTheSummary() async {
        let platform = FakeFocusPlatform(title: "Inbox", rule: .never)
        let outcome = await sequence(platform).run(target: target)
        #expect(outcome == .focusDidNotMove(target.settingTitle("Inbox")))

        let calls = platform.calls
        #expect(calls.filter { $0 == .raise }.count == 2)
        #expect(calls.filter { $0 == .activate(321) }.count == 1)
        #expect(calls.filter { $0 == .frontmost }.count == 1)
    }

    @Test func eachMethodWaitsAboutTheFullTimeoutBeforeGivingUp() async {
        let polling = FocusPolling(interval: .milliseconds(5), timeout: .milliseconds(60))
        let platform = FakeFocusPlatform(rule: .never)
        let clock = ContinuousClock()
        let started = clock.now
        _ = await FocusSequence(platform: platform, polling: polling).run(target: target)
        let elapsed = started.duration(to: clock.now)
        #expect(elapsed >= .milliseconds(110))
        #expect(elapsed < .seconds(5))  // only guards against a hang; CI runners can be slow
    }

    @Test func cancellationEndsTheSequenceWithoutTryingTheNextMethod() async {
        let polling = FocusPolling(interval: .milliseconds(5), timeout: .seconds(5))
        let platform = FakeFocusPlatform(rule: .never)
        let task = Task { await FocusSequence(platform: platform, polling: polling).run(target: target) }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(!platform.calls.contains(.frontmost))
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
