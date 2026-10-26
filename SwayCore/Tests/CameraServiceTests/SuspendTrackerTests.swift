import SwayModels
import Testing

@testable import CameraService

@Suite("Suspend and resume reason set")
struct SuspendTrackerTests {
    private func runningTracker() -> SuspendTracker {
        var tracker = SuspendTracker()
        #expect(tracker.captureRequested() == .resume)
        return tracker
    }

    @Test func startingWithNoReasonsMeansBuildTheSession() {
        var tracker = SuspendTracker()
        #expect(tracker.captureRequested() == .resume)
        #expect(tracker.isCaptureRequested)
        #expect(!tracker.isSuspended)
    }

    @Test func firstReasonSuspendsAndLastClearedReasonResumes() {
        var tracker = runningTracker()
        #expect(tracker.begin(.screenLocked) == .suspend(.screenLocked))
        #expect(tracker.isSuspended)
        #expect(tracker.end(.screenLocked) == .resume)
        #expect(!tracker.isSuspended)
    }

    @Test(arguments: [SuspendReason.systemSleep, .displaysAsleep, .screenLocked, .sessionInactive])
    func eachReasonRoundTrips(reason: SuspendReason) {
        var tracker = runningTracker()
        #expect(tracker.begin(reason) == .suspend(reason))
        #expect(tracker.end(reason) == .resume)
    }

    @Test func overlappingReasonsResumeOnlyWhenAllAreCleared() {
        var tracker = runningTracker()
        #expect(tracker.begin(.screenLocked) == .suspend(.screenLocked))
        #expect(tracker.begin(.displaysAsleep) == .none)
        #expect(tracker.begin(.systemSleep) == .none)

        #expect(tracker.end(.systemSleep) == .none)
        #expect(tracker.isSuspended)
        #expect(tracker.end(.displaysAsleep) == .none)
        #expect(tracker.isSuspended)
        #expect(tracker.end(.screenLocked) == .resume)
        #expect(!tracker.isSuspended)
    }

    @Test func clearingTheFirstReasonReportsTheNextOne() {
        var tracker = runningTracker()
        _ = tracker.begin(.screenLocked)
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.firstReason == .screenLocked)
        #expect(tracker.end(.screenLocked) == .reasonChanged(.displaysAsleep))
        #expect(tracker.firstReason == .displaysAsleep)
        #expect(tracker.end(.displaysAsleep) == .resume)
    }

    @Test func clearingALaterReasonDoesNotChangeTheReportedOne() {
        var tracker = runningTracker()
        _ = tracker.begin(.systemSleep)
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.end(.displaysAsleep) == .none)
        #expect(tracker.firstReason == .systemSleep)
    }

    @Test func repeatedBeginIsIgnored() {
        var tracker = runningTracker()
        #expect(tracker.begin(.screenLocked) == .suspend(.screenLocked))
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(tracker.reasons == [.screenLocked])
        #expect(tracker.end(.screenLocked) == .resume)
    }

    @Test func endingAReasonThatIsNotActiveDoesNothing() {
        var tracker = runningTracker()
        #expect(tracker.end(.systemSleep) == .none)
        _ = tracker.begin(.screenLocked)
        #expect(tracker.end(.systemSleep) == .none)
        #expect(tracker.isSuspended)
    }

    @Test func noResumeAfterStop() {
        var tracker = runningTracker()
        _ = tracker.begin(.systemSleep)
        tracker.captureStopped()
        #expect(!tracker.isCaptureRequested)
        // The Mac is still asleep, so the reason stays; ending it later resumes nothing.
        #expect(tracker.isSuspended)
        #expect(tracker.end(.systemSleep) == .none)
        #expect(!tracker.isSuspended)
    }

    @Test func reasonsArrivingAfterStopAreRecordedButChangeNothing() {
        var tracker = runningTracker()
        tracker.captureStopped()
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(tracker.reasons == [.screenLocked])
        #expect(tracker.end(.screenLocked) == .none)
        #expect(!tracker.isSuspended)
    }

    @Test func startingAgainAfterStopStillSeesTheActiveReasons() {
        var tracker = runningTracker()
        _ = tracker.begin(.screenLocked)
        tracker.captureStopped()
        #expect(tracker.reasons == [.screenLocked])
        #expect(tracker.captureRequested() == .suspend(.screenLocked))
    }

    /// The audit finding: the camera came on at the lock screen. Start, lock, stop, start again must not build.
    @Test func startLockStopStartDoesNotTurnTheCameraOn() {
        var tracker = SuspendTracker()
        #expect(tracker.captureRequested() == .resume)
        #expect(tracker.begin(.screenLocked) == .suspend(.screenLocked))
        tracker.captureStopped()
        #expect(tracker.captureRequested() == .suspend(.screenLocked))
        // Unlocking now resumes the capture that was asked for.
        #expect(tracker.end(.screenLocked) == .resume)
    }

    @Test func aReasonEndedWhileStoppedIsClearedAndTheNextStartBuilds() {
        var tracker = runningTracker()
        _ = tracker.begin(.screenLocked)
        tracker.captureStopped()
        #expect(tracker.end(.screenLocked) == .none)
        #expect(tracker.reasons.isEmpty)
        #expect(tracker.captureRequested() == .resume)
    }

    @Test func aReasonBegunWhileStoppedBlocksTheNextStart() {
        var tracker = runningTracker()
        tracker.captureStopped()
        #expect(tracker.begin(.displaysAsleep) == .none)
        #expect(tracker.captureRequested() == .suspend(.displaysAsleep))
    }

    @Test func reasonsOverlappingAStopKeepTheirOrder() {
        var tracker = runningTracker()
        _ = tracker.begin(.systemSleep)
        tracker.captureStopped()
        _ = tracker.begin(.screenLocked)
        #expect(tracker.end(.systemSleep) == .none)
        #expect(tracker.captureRequested() == .suspend(.screenLocked))
    }

    @Test func startingWhileSuspendedStaysSuspended() {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        // A restart with new parameters while suspended must not turn the camera on.
        #expect(tracker.captureRequested() == .suspend(.displaysAsleep))
        #expect(tracker.end(.displaysAsleep) == .resume)
    }

    @Test func reasonsBeforeTheFirstStartAreRecorded() {
        var tracker = SuspendTracker()
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(tracker.isSuspended)
        #expect(tracker.captureRequested() == .suspend(.screenLocked))
    }

    @Test func aReasonThatEndedBeforeTheFirstStartDoesNotBlockIt() {
        var tracker = SuspendTracker()
        #expect(tracker.begin(.systemSleep) == .none)
        #expect(tracker.end(.systemSleep) == .none)
        #expect(tracker.captureRequested() == .resume)
    }

    @Test func sessionInactiveHoldsCaptureOffUntilTheSessionReturns() {
        var tracker = runningTracker()
        #expect(tracker.begin(.sessionInactive) == .suspend(.sessionInactive))
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(tracker.end(.sessionInactive) == .reasonChanged(.screenLocked))
        #expect(tracker.end(.screenLocked) == .resume)
    }

    @Test func severalReasonsEndingTogetherGiveOneCombinedDirective() {
        var tracker = runningTracker()
        _ = tracker.begin(.systemSleep)
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.end([.systemSleep, .displaysAsleep]) == .resume)

        _ = tracker.begin(.systemSleep)
        _ = tracker.begin(.screenLocked)
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.end([.systemSleep, .displaysAsleep]) == .reasonChanged(.screenLocked))
        #expect(tracker.end([.systemSleep, .displaysAsleep]) == .none)
    }

    @Test func realisticLidCloseSequence() {
        var tracker = runningTracker()
        #expect(tracker.begin(.screenLocked) == .suspend(.screenLocked))
        #expect(tracker.begin(.displaysAsleep) == .none)
        #expect(tracker.begin(.systemSleep) == .none)
        #expect(tracker.end(.systemSleep) == .none)
        #expect(tracker.end(.displaysAsleep) == .none)
        #expect(tracker.end(.screenLocked) == .resume)
    }

    // MARK: Events and the self-heal for a missed display wake

    private static let endEvents: [SuspendTracker.Event] = [
        .end(.systemSleep), .end(.displaysAsleep), .end(.screenLocked), .end(.sessionInactive),
    ]

    @Test func eventsMapToBeginAndEnd() {
        var tracker = runningTracker()
        #expect(tracker.apply(.begin(.screenLocked), isMainDisplayAsleep: { false }) == .suspend(.screenLocked))
        #expect(tracker.apply(.end(.screenLocked), isMainDisplayAsleep: { false }) == .resume)
    }

    @Test(arguments: [SuspendReason.systemSleep, .screenLocked, .sessionInactive])
    func aWakeClearsAMissedDisplayWakeWhenTheDisplayIsAwake(reason: SuspendReason) {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        _ = tracker.begin(reason)
        // The event's own reason and the stale `.displaysAsleep` clear together: one `.resume`, no flicker.
        #expect(tracker.apply(.end(reason), isMainDisplayAsleep: { false }) == .resume)
        #expect(tracker.reasons.isEmpty)
    }

    @Test(arguments: [SuspendReason.systemSleep, .screenLocked, .sessionInactive])
    func aWakeKeepsDisplaysAsleepWhileTheDisplayIsStillAsleep(reason: SuspendReason) {
        var tracker = runningTracker()
        _ = tracker.begin(reason)
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.apply(.end(reason), isMainDisplayAsleep: { true }) == .reasonChanged(.displaysAsleep))
        #expect(tracker.reasons == [.displaysAsleep])
    }

    @Test func healingOnlyClearsDisplaysAsleepAndLeavesOtherReasons() {
        var tracker = runningTracker()
        _ = tracker.begin(.screenLocked)
        _ = tracker.begin(.displaysAsleep)
        _ = tracker.begin(.sessionInactive)
        #expect(tracker.apply(.end(.systemSleep), isMainDisplayAsleep: { false }) == .none)
        #expect(tracker.reasons == [.screenLocked, .sessionInactive])
    }

    @Test func healingReportsTheNextReasonWhenTheFirstWasTheStaleOne() {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        _ = tracker.begin(.screenLocked)
        #expect(tracker.apply(.end(.systemSleep), isMainDisplayAsleep: { false }) == .reasonChanged(.screenLocked))
    }

    @Test func beginEventsNeverHeal() {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        #expect(tracker.apply(.begin(.screenLocked), isMainDisplayAsleep: { false }) == .none)
        #expect(tracker.reasons == [.displaysAsleep, .screenLocked])
    }

    @Test func healingWhileStoppedClearsTheReasonAndResumesNothing() {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        _ = tracker.begin(.systemSleep)
        tracker.captureStopped()
        #expect(tracker.apply(.end(.systemSleep), isMainDisplayAsleep: { false }) == .none)
        #expect(tracker.reasons.isEmpty)
        #expect(tracker.captureRequested() == .resume)
    }

    @Test func theDisplayCheckRunsOnlyWhenItCanMatter() {
        var tracker = runningTracker()
        var checks = 0
        let countingCheck: () -> Bool = {
            checks += 1
            return false
        }
        // No `.displaysAsleep` to heal.
        _ = tracker.begin(.systemSleep)
        _ = tracker.apply(.end(.systemSleep), isMainDisplayAsleep: countingCheck)
        // The display wake itself needs no heal.
        _ = tracker.begin(.displaysAsleep)
        _ = tracker.apply(.end(.displaysAsleep), isMainDisplayAsleep: countingCheck)
        // Begin events never look at the display.
        _ = tracker.apply(.begin(.screenLocked), isMainDisplayAsleep: countingCheck)
        #expect(checks == 0)

        _ = tracker.begin(.displaysAsleep)
        _ = tracker.apply(.end(.screenLocked), isMainDisplayAsleep: countingCheck)
        #expect(checks == 1)
    }

    // MARK: The privacy invariant

    private enum Step: CustomStringConvertible {
        case request
        case stop
        case event(SuspendTracker.Event, displayAsleep: Bool)

        var description: String {
            switch self {
            case .request: "request"
            case .stop: "stop"
            case .event(let event, let asleep): "\(event)\(asleep ? "" : "+awake")"
            }
        }

        static let all: [Step] = {
            let reasons: [SuspendReason] = [.systemSleep, .displaysAsleep, .screenLocked, .sessionInactive]
            var steps: [Step] = [.request, .stop]
            for reason in reasons {
                steps.append(.event(.begin(reason), displayAsleep: true))
                steps.append(.event(.end(reason), displayAsleep: true))
                steps.append(.event(.end(reason), displayAsleep: false))
            }
            return steps
        }()
    }

    /// Whatever the order of starts, stops, and system events, a session is up exactly when capture is requested and
    /// no reason is active. A session never exists while any reason is active (D43).
    @Test func noSequenceOfStartsStopsAndEventsKeepsASessionUpWhileSuspended() {
        var failure: String?
        var sequences = 0

        func explore(_ tracker: SuspendTracker, sessionUp: Bool, path: [Step], remaining: Int) {
            guard failure == nil else { return }
            sequences += 1
            let shouldBeUp = tracker.isCaptureRequested && !tracker.isSuspended
            if sessionUp != shouldBeUp {
                failure = "after \(path): session up = \(sessionUp), reasons = \(tracker.reasons)"
                return
            }
            guard remaining > 0 else { return }
            for step in Step.all {
                var next = tracker
                var up = sessionUp
                switch step {
                case .request:
                    up = Self.sessionState(after: next.captureRequested(), was: up)
                case .stop:
                    next.captureStopped()
                    up = false
                case .event(let event, let asleep):
                    up = Self.sessionState(after: next.apply(event, isMainDisplayAsleep: { asleep }), was: up)
                }
                explore(next, sessionUp: up, path: path + [step], remaining: remaining - 1)
            }
        }

        explore(SuspendTracker(), sessionUp: false, path: [], remaining: 4)
        #expect(failure == nil, "\(failure ?? "")")
        #expect(sequences > 1000)
    }

    /// What the owner does with each directive: `.resume` builds a session, `.suspend` tears it down.
    private static func sessionState(after directive: SuspendTracker.Directive, was sessionUp: Bool) -> Bool {
        switch directive {
        case .resume: true
        case .suspend: false
        case .none, .reasonChanged: sessionUp
        }
    }
}
