import Foundation

/// A pending one-shot delayed action. Cancelling it after it ran, or twice, does nothing.
struct ScheduledAction {
    /// Stops the action from running if it has not run yet.
    let cancel: @MainActor () -> Void
}

/// Runs a closure once, a little later, on the main actor (the display and Space holds, the coalesced camera list
/// refresh, the camera grace, the USB camera wait). A protocol so tests move time by hand instead of sleeping.
@MainActor
protocol DelayScheduling: AnyObject {
    /// Runs `work` once, `delay` seconds from now. The returned action cancels it.
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledAction
}

/// The real timer: one sleeping task per scheduled action, so nothing wakes while nothing is pending.
@MainActor
final class TaskDelayScheduler: DelayScheduling {
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledAction {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            work()
        }
        return ScheduledAction { task.cancel() }
    }
}
