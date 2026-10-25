import Testing

@testable import CameraService

@Suite("Frame watchdog")
struct FrameWatchdogTests {
    private func armed(at time: Double = 0) -> FrameWatchdog {
        var watchdog = FrameWatchdog()
        watchdog.arm(at: time)
        return watchdog
    }

    @Test func defaultsMatchTheContract() {
        let watchdog = FrameWatchdog()
        #expect(watchdog.timeout == 3)
        #expect(watchdog.retryInterval == 10)
        #expect(!watchdog.isArmed)
    }

    @Test func idleWatchdogIgnoresEverything() {
        var watchdog = FrameWatchdog()
        #expect(watchdog.check(at: 100) == nil)
        #expect(watchdog.frameReceived(at: 100) == nil)
        #expect(watchdog.markInterrupted(at: 100) == nil)
    }

    @Test func firstFrameAfterArmingReportsResumed() {
        var watchdog = armed()
        #expect(watchdog.frameReceived(at: 0.2) == .resumed)
        #expect(watchdog.frameReceived(at: 0.3) == nil)
    }

    @Test func steadyFramesNeverStall() {
        var watchdog = armed()
        _ = watchdog.frameReceived(at: 0.1)
        for tick in 1...30 {
            let time = Double(tick)
            #expect(watchdog.frameReceived(at: time) == nil)
            #expect(watchdog.check(at: time + 0.5) == nil)
        }
        #expect(!watchdog.isStalled)
    }

    @Test func noFramesForThreeSecondsStalls() {
        var watchdog = armed()
        _ = watchdog.frameReceived(at: 1)
        #expect(watchdog.check(at: 3.9) == nil)
        #expect(watchdog.check(at: 4.0) == .stalled)
        #expect(watchdog.isStalled)
    }

    @Test func neverReceivingAFrameStallsFromTheArmTime() {
        var watchdog = armed(at: 10)
        #expect(watchdog.check(at: 12.9) == nil)
        #expect(watchdog.check(at: 13) == .stalled)
    }

    @Test func stallIsReportedOnlyOnce() {
        var watchdog = armed()
        #expect(watchdog.check(at: 3) == .stalled)
        #expect(watchdog.check(at: 4) == nil)
        #expect(watchdog.check(at: 12.9) == nil)
    }

    @Test func retryIsDueEveryTenSecondsWhileStalled() {
        var watchdog = armed()
        #expect(watchdog.check(at: 3) == .stalled)
        #expect(watchdog.check(at: 12.9) == nil)
        #expect(watchdog.check(at: 13) == .retryDue)
        #expect(watchdog.check(at: 22.9) == nil)
        #expect(watchdog.check(at: 23) == .retryDue)
    }

    @Test func framesAfterAStallReportResumedThenStayQuiet() {
        var watchdog = armed()
        _ = watchdog.frameReceived(at: 0.1)
        #expect(watchdog.check(at: 3.2) == .stalled)
        #expect(watchdog.frameReceived(at: 5) == .resumed)
        #expect(!watchdog.isStalled)
        #expect(watchdog.frameReceived(at: 5.1) == nil)
        #expect(watchdog.check(at: 6) == nil)
    }

    @Test func rearmingKeepsAStallSoTheNextFrameResumes() {
        var watchdog = armed()
        #expect(watchdog.check(at: 3) == .stalled)
        watchdog.arm(at: 13)
        #expect(watchdog.isStalled)
        #expect(watchdog.check(at: 22.9) == nil)
        #expect(watchdog.check(at: 23) == .retryDue)
        #expect(watchdog.frameReceived(at: 23.5) == .resumed)
    }

    @Test func rearmingAHealthyWatchdogWaitsForTheFirstFrameAgain() {
        var watchdog = armed()
        _ = watchdog.frameReceived(at: 1)
        watchdog.arm(at: 50)
        #expect(!watchdog.isStalled)
        #expect(watchdog.check(at: 52.9) == nil)
        #expect(watchdog.check(at: 53) == .stalled)
    }

    @Test func disarmForgetsTheStall() {
        var watchdog = armed()
        #expect(watchdog.check(at: 3) == .stalled)
        watchdog.disarm()
        #expect(!watchdog.isArmed)
        #expect(!watchdog.isStalled)
        #expect(watchdog.check(at: 100) == nil)
        watchdog.arm(at: 100)
        #expect(!watchdog.isStalled)
    }

    @Test func interruptionStallsImmediatelyAndNextFrameResumes() {
        var watchdog = armed()
        _ = watchdog.frameReceived(at: 1)
        #expect(watchdog.markInterrupted(at: 1.5) == .stalled)
        #expect(watchdog.markInterrupted(at: 1.6) == nil)
        #expect(watchdog.isStalled)
        #expect(watchdog.frameReceived(at: 2) == .resumed)
    }

    @Test func customTimeoutIsHonored() {
        var watchdog = FrameWatchdog(timeout: 1, retryInterval: 2)
        watchdog.arm(at: 0)
        #expect(watchdog.check(at: 1) == .stalled)
        #expect(watchdog.check(at: 3) == .retryDue)
    }
}
