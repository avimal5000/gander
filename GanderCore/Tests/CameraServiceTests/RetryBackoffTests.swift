import Testing

@testable import CameraService

@Suite("Retry backoff")
struct RetryBackoffTests {
    @Test func openFailuresBackOffFromOneToTenSeconds() {
        var backoff = RetryBackoff()
        let delays = (0..<7).map { _ in backoff.nextOpenFailureDelay() }
        #expect(delays == [1, 2, 5, 10, 10, 10, 10])
    }

    @Test func stallRebuildsBackOffFromTenToSixtySeconds() {
        var backoff = RetryBackoff()
        let delays = (0..<6).map { _ in backoff.nextStallRebuildDelay() }
        #expect(delays == [10, 30, 60, 60, 60, 60])
    }

    @Test func theTwoSequencesAdvanceIndependently() {
        var backoff = RetryBackoff()
        #expect(backoff.nextOpenFailureDelay() == 1)
        #expect(backoff.nextOpenFailureDelay() == 2)
        #expect(backoff.nextStallRebuildDelay() == 10)
        #expect(backoff.nextOpenFailureDelay() == 5)
        #expect(backoff.nextStallRebuildDelay() == 30)
    }

    @Test func framesResetBothSequences() {
        var backoff = RetryBackoff()
        for _ in 0..<5 {
            _ = backoff.nextOpenFailureDelay()
            _ = backoff.nextStallRebuildDelay()
        }
        backoff.framesFlowed()
        #expect(backoff == RetryBackoff())
        #expect(backoff.nextOpenFailureDelay() == 1)
        #expect(backoff.nextStallRebuildDelay() == 10)
    }

    @Test func aLongRunNeverGrowsPastTheLastDelayOrOverflows() {
        var backoff = RetryBackoff()
        var last = 0.0
        for _ in 0..<10_000 {
            _ = backoff.nextStallRebuildDelay()
            last = backoff.nextOpenFailureDelay()
        }
        #expect(last == 10)
        #expect(backoff.nextStallRebuildDelay() == 60)
    }

    @Test func theFirstStallDelayIsTheWatchdogDefault() {
        #expect(RetryBackoff.stallRebuildDelays.first == FrameWatchdog.defaultRetryInterval)
    }
}
