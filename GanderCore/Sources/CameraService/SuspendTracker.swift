import GanderModels

/// The reason-set state machine behind sleep/lock suspension (PLAN.md privacy guarantee, SPEC D43).
///
/// It tracks which `SuspendReason`s are active and whether the caller wants capture. It performs no I/O: it
/// only says what the owner should do, so the rules are testable without a camera.
///
/// - Capture is torn down when the first reason arrives and rebuilt only when every reason has cleared.
/// - Reasons are ordered by arrival; the status reports the earliest one still active.
/// - Suspension is sticky: reasons are recorded and cleared whether or not capture is requested, and
///   `captureStopped()` keeps them. A later `captureRequested()` therefore answers `.suspend` while the Mac is
///   still asleep or locked, and an `end` that arrives while capture is stopped clears its reason without
///   resuming anything (it returns `.none`, because nobody asked for capture).
struct SuspendTracker: Sendable, Equatable {
    /// What the owner must do after an input.
    enum Directive: Sendable, Equatable {
        /// Nothing to do.
        case none
        /// Tear the session down completely and report `.suspended(reason)`.
        case suspend(SuspendReason)
        /// Already torn down; only the reported reason changed.
        case reasonChanged(SuspendReason)
        /// Build the session and report `.starting`.
        case resume
    }

    /// A system condition that began or ended, as the notifications report it.
    enum Event: Sendable, Equatable {
        case begin(SuspendReason)
        case end(SuspendReason)
    }

    /// Active reasons, oldest first, without duplicates.
    private(set) var reasons: [SuspendReason] = []
    /// True between `captureRequested()` and `captureStopped()`.
    private(set) var isCaptureRequested = false

    /// True while at least one reason is active.
    var isSuspended: Bool { !reasons.isEmpty }
    /// The reason reported in `.suspended`.
    var firstReason: SuspendReason? { reasons.first }

    /// The caller started (or restarted) capture. Returns `.suspend` if a reason is already active, else
    /// `.resume`, which here means "build the session now".
    mutating func captureRequested() -> Directive {
        isCaptureRequested = true
        if let first = reasons.first { return .suspend(first) }
        return .resume
    }

    /// The caller stopped capture. Active reasons stay: the Mac is still asleep or locked, and the next
    /// `captureRequested()` must see that.
    mutating func captureStopped() {
        isCaptureRequested = false
    }

    /// A suspend condition began (sleep, display sleep, screen lock, or another user's session). Recorded even
    /// while capture is not requested; the directive is `.none` then.
    mutating func begin(_ reason: SuspendReason) -> Directive {
        guard !reasons.contains(reason) else { return .none }
        let wasSuspended = isSuspended
        reasons.append(reason)
        guard isCaptureRequested, !wasSuspended else { return .none }
        return .suspend(reason)
    }

    /// A suspend condition ended (wake, unlock, or the other user's session left). Cleared even while capture is
    /// not requested; the directive is `.none` then.
    mutating func end(_ reason: SuspendReason) -> Directive {
        end([reason])
    }

    /// Several conditions ended at the same moment. The directive describes the combined change, so the owner
    /// never sees an intermediate `.reasonChanged` for a reason that is cleared in the same step.
    mutating func end(_ ended: [SuspendReason]) -> Directive {
        let previousFirst = reasons.first
        reasons.removeAll { ended.contains($0) }
        guard isCaptureRequested, previousFirst != nil else { return .none }
        guard let newFirst = reasons.first else { return .resume }
        return newFirst == previousFirst ? .none : .reasonChanged(newFirst)
    }

    /// Applies a system event, with the self-heal for a missed display wake: when any condition ends and the main
    /// display is awake (`isMainDisplayAsleep` says so), `.displaysAsleep` is cleared too. A lost
    /// `screensDidWake` must not leave capture suspended. The check runs only when it can matter.
    mutating func apply(_ event: Event, isMainDisplayAsleep: () -> Bool) -> Directive {
        switch event {
        case .begin(let reason):
            return begin(reason)
        case .end(let reason):
            var ended = [reason]
            if reason != .displaysAsleep, reasons.contains(.displaysAsleep), !isMainDisplayAsleep() {
                ended.append(.displaysAsleep)
            }
            return end(ended)
        }
    }
}
