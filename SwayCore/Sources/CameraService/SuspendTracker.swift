import SwayModels

/// The reason-set state machine behind sleep/lock suspension (PLAN.md privacy guarantee).
///
/// It tracks which `SuspendReason`s are active and whether the caller wants capture. It performs no I/O: it
/// only says what the owner should do, so the rules are testable without a camera.
///
/// - Capture is torn down when the first reason arrives and rebuilt only when every reason has cleared.
/// - Reasons are ordered by arrival; the status reports the earliest one still active.
/// - After `captureStopped()` nothing ever resumes capture, and incoming reasons are ignored.
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

    /// The caller stopped capture. Forgets every reason; later `end` calls cannot resume anything.
    mutating func captureStopped() {
        isCaptureRequested = false
        reasons.removeAll()
    }

    /// A suspend condition began (sleep, display sleep, or screen lock).
    mutating func begin(_ reason: SuspendReason) -> Directive {
        guard isCaptureRequested, !reasons.contains(reason) else { return .none }
        let wasSuspended = isSuspended
        reasons.append(reason)
        return wasSuspended ? .none : .suspend(reason)
    }

    /// A suspend condition ended (wake or unlock).
    mutating func end(_ reason: SuspendReason) -> Directive {
        guard isCaptureRequested, let index = reasons.firstIndex(of: reason) else { return .none }
        let previousFirst = reasons.first
        reasons.remove(at: index)
        guard let newFirst = reasons.first else { return .resume }
        return newFirst == previousFirst ? .none : .reasonChanged(newFirst)
    }
}
