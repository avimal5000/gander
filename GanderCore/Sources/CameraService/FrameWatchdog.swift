import Foundation

/// Detects a camera that stops delivering frames (CONTRACT 6.1: no frames for 3 s while running).
///
/// Pure state over caller-supplied timestamps (any monotonic clock, in seconds), so it needs no timers in
/// tests. The capture service calls `frameReceived` from the frame queue and `check` once per second.
struct FrameWatchdog: Sendable, Equatable {
    /// A transition the owner reacts to.
    enum Event: Sendable, Equatable {
        /// No frames for `timeout` seconds. Report `.interrupted`.
        case stalled
        /// Still stalled and `retryInterval` seconds passed since the last attempt. Restart the session.
        case retryDue
        /// A frame arrived after waiting for the first frame or after a stall. Report `.running`.
        case resumed
    }

    static let defaultTimeout: TimeInterval = 3
    static let defaultRetryInterval: TimeInterval = 10

    private enum Phase: Sendable, Equatable {
        case idle
        case awaitingFrames(since: TimeInterval)
        case flowing(lastFrame: TimeInterval)
        case stalled(lastAttempt: TimeInterval)
    }

    let timeout: TimeInterval
    /// How long a stall waits before the next `.retryDue`. The owner lengthens it between attempts (`RetryBackoff`).
    private(set) var retryInterval: TimeInterval
    private var phase = Phase.idle

    init(timeout: TimeInterval = defaultTimeout, retryInterval: TimeInterval = defaultRetryInterval) {
        self.timeout = timeout
        self.retryInterval = retryInterval
    }

    /// Sets the wait before the next `.retryDue`. It applies from the last attempt (or the stall) already in progress.
    mutating func setRetryInterval(_ interval: TimeInterval) {
        retryInterval = interval
    }

    /// True while the camera is considered stalled.
    var isStalled: Bool {
        if case .stalled = phase { return true }
        return false
    }

    /// True when a session is being watched.
    var isArmed: Bool { phase != .idle }

    /// Starts watching a freshly started session. A stall in progress is kept (so the first frame still
    /// reports `.resumed`) and its retry clock restarts.
    mutating func arm(at now: TimeInterval) {
        phase = isStalled ? .stalled(lastAttempt: now) : .awaitingFrames(since: now)
    }

    /// Stops watching (session torn down). Forgets any stall.
    mutating func disarm() {
        phase = .idle
    }

    /// Records a frame. Returns `.resumed` when this ends a wait or a stall.
    mutating func frameReceived(at now: TimeInterval) -> Event? {
        switch phase {
        case .idle:
            return nil
        case .flowing:
            phase = .flowing(lastFrame: now)
            return nil
        case .awaitingFrames, .stalled:
            phase = .flowing(lastFrame: now)
            return .resumed
        }
    }

    /// Periodic check. Returns `.stalled` the first time the timeout passes and `.retryDue` every
    /// `retryInterval` after that.
    mutating func check(at now: TimeInterval) -> Event? {
        switch phase {
        case .idle:
            return nil
        case .awaitingFrames(let since):
            guard now - since >= timeout else { return nil }
            phase = .stalled(lastAttempt: now)
            return .stalled
        case .flowing(let lastFrame):
            guard now - lastFrame >= timeout else { return nil }
            phase = .stalled(lastAttempt: now)
            return .stalled
        case .stalled(let lastAttempt):
            guard now - lastAttempt >= retryInterval else { return nil }
            phase = .stalled(lastAttempt: now)
            return .retryDue
        }
    }

    /// The system told us the session was interrupted: treat it as stalled right away so the next frame
    /// reports `.resumed`. Returns `.stalled` unless already stalled or not armed.
    mutating func markInterrupted(at now: TimeInterval) -> Event? {
        switch phase {
        case .idle, .stalled:
            return nil
        case .awaitingFrames, .flowing:
            phase = .stalled(lastAttempt: now)
            return .stalled
        }
    }
}
