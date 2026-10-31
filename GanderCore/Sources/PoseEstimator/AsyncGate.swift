import Foundation
import os

/// A first-in-first-out async mutex. `LivePoseSource` uses it to run `start` and `stop` one at a time, so an
/// in-flight start can never interleave with a stop and leave the camera running with no owner.
///
/// Pair every `acquire()` with exactly one `release()`.
final class AsyncGate: Sendable {
    private struct State {
        var isHeld = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Suspends until the gate is free, then holds it.
    func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let acquiredImmediately = state.withLock { state -> Bool in
                if state.isHeld {
                    state.waiters.append(continuation)
                    return false
                }
                state.isHeld = true
                return true
            }
            if acquiredImmediately { continuation.resume() }
        }
    }

    /// Frees the gate, or hands it straight to the longest-waiting caller.
    func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            if state.waiters.isEmpty {
                state.isHeld = false
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.resume()
    }
}
