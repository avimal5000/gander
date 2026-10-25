import Foundation
import os

@testable import SwayUI

/// A manually advanced monotonic clock. Tests move time with `advance(by:)` instead of sleeping.
final class TestClock: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: TimeInterval(0))

    var now: TimeInterval { state.withLock { $0 } }

    func set(_ time: TimeInterval) {
        state.withLock { $0 = time }
    }

    func advance(by delta: TimeInterval) {
        state.withLock { $0 += delta }
    }

    /// The clock as the closure type the gate state machine takes.
    var reading: GateClock {
        { [self] in now }
    }
}
