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

    @Test(arguments: [SuspendReason.systemSleep, .displaysAsleep, .screenLocked])
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
        #expect(!tracker.isSuspended)
        #expect(tracker.end(.systemSleep) == .none)
    }

    @Test func reasonsArrivingAfterStopAreIgnored() {
        var tracker = runningTracker()
        tracker.captureStopped()
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(!tracker.isSuspended)
        #expect(tracker.end(.screenLocked) == .none)
    }

    @Test func startingAgainAfterStopBeginsFresh() {
        var tracker = runningTracker()
        _ = tracker.begin(.screenLocked)
        tracker.captureStopped()
        #expect(tracker.captureRequested() == .resume)
        #expect(tracker.reasons.isEmpty)
    }

    @Test func startingWhileSuspendedStaysSuspended() {
        var tracker = runningTracker()
        _ = tracker.begin(.displaysAsleep)
        // A restart with new parameters while suspended must not turn the camera on.
        #expect(tracker.captureRequested() == .suspend(.displaysAsleep))
        #expect(tracker.end(.displaysAsleep) == .resume)
    }

    @Test func reasonsBeforeTheFirstStartAreIgnored() {
        var tracker = SuspendTracker()
        #expect(tracker.begin(.screenLocked) == .none)
        #expect(!tracker.isSuspended)
        #expect(tracker.captureRequested() == .resume)
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
}
