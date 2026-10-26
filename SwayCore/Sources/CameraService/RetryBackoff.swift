import Foundation

/// How long to wait before the next try at a camera that is not working (SPEC D47).
///
/// Two independent sequences, each growing with every failure and ending in a delay that repeats forever:
/// - failing to find or open the device: 1 s, 2 s, 5 s, then 10 s;
/// - rebuilding a stalled camera (the session runs but no frames arrive): 10 s, 30 s, then 60 s.
///
/// Frames flowing again end the trouble, so `framesFlowed()` starts both sequences over. The one-time retry after
/// a runtime error is `RuntimeRetryPolicy`'s business, not this type's.
struct RetryBackoff: Sendable, Equatable {
    static let openFailureDelays: [TimeInterval] = [1, 2, 5, 10]
    static let stallRebuildDelays: [TimeInterval] = [10, 30, 60]

    private var openFailures = 0
    private var stallWaits = 0

    /// The device could not be found or opened. Returns how long to wait before the next try and moves on to the
    /// next delay.
    mutating func nextOpenFailureDelay() -> TimeInterval {
        let delay = Self.delay(in: Self.openFailureDelays, at: openFailures)
        openFailures = min(openFailures + 1, Self.openFailureDelays.count)
        return delay
    }

    /// A stall began, or a rebuild did not bring frames back. Returns how long to wait before rebuilding the
    /// session again and moves on to the next delay.
    mutating func nextStallRebuildDelay() -> TimeInterval {
        let delay = Self.delay(in: Self.stallRebuildDelays, at: stallWaits)
        stallWaits = min(stallWaits + 1, Self.stallRebuildDelays.count)
        return delay
    }

    /// Frames are flowing: both sequences start over.
    mutating func framesFlowed() {
        self = RetryBackoff()
    }

    /// The delay at `index`, or the last one once the sequence has run out.
    private static func delay(in delays: [TimeInterval], at index: Int) -> TimeInterval {
        delays[min(index, delays.count - 1)]
    }
}
