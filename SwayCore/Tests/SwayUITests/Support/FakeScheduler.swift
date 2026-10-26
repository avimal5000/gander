import Foundation

@testable import SwayUI

/// Delayed work whose time the test moves by hand. Nothing runs until `advance(by:)` reaches it, so no test sleeps.
@MainActor
final class FakeScheduler: DelayScheduling {
    private struct Entry {
        let id: Int
        let due: TimeInterval
        let delay: TimeInterval
        let work: @MainActor () -> Void
    }

    private var entries: [Entry] = []
    private var nextID = 0
    /// Seconds moved forward so far.
    private(set) var now: TimeInterval = 0
    /// The delay of every action ever scheduled, in order.
    private(set) var scheduledDelays: [TimeInterval] = []

    /// The delays of the actions still waiting, soonest first.
    var pendingDelays: [TimeInterval] {
        entries.sorted { ($0.due, $0.id) < ($1.due, $1.id) }.map(\.delay)
    }

    var hasPending: Bool { !entries.isEmpty }

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledAction {
        nextID += 1
        let id = nextID
        entries.append(Entry(id: id, due: now + delay, delay: delay, work: work))
        scheduledDelays.append(delay)
        return ScheduledAction { [weak self] in self?.entries.removeAll { $0.id == id } }
    }

    /// Moves time forward by `seconds`, running whatever falls due on the way in due order. Work that schedules more
    /// work gets it run too when it falls inside the span.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = entries.filter({ $0.due <= target + 1e-9 }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            entries.removeAll { $0.id == next.id }
            now = max(now, next.due)
            next.work()
        }
        now = target
    }
}
