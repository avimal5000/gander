import Foundation
import SwayModels
import os

/// A focus controller that never touches Accessibility, windows, or the prompt. `focus(display:in:)` can be held
/// open so a test sees a request in flight.
final class FakeFocus: FocusControlling {
    struct State: Sendable {
        var trusted: Bool
        var isTrustedCalls = 0
        var requestTrustCalls = 0
        var windows: [DisplayID: WindowSummary] = [:]
        var focusedDisplay: DisplayID?
        var lastUsedWindowsCalls = 0
        var focusedDisplayCalls = 0
        var focusCalls: [DisplayID] = []
        var layouts: [DisplayLayout] = []
        var result: FocusResult = .noWindow("none")
        var holdsFocus = false
        var released = false
        var waiter: CheckedContinuation<Void, Never>?
        /// For each `focus` call, whether its task was cancelled by the time it returned.
        var focusCancelled: [Bool] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(trusted: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: State(trusted: trusted))
    }

    var isTrustedCalls: Int { state.withLock { $0.isTrustedCalls } }
    var requestTrustCalls: Int { state.withLock { $0.requestTrustCalls } }
    var lastUsedWindowsCalls: Int { state.withLock { $0.lastUsedWindowsCalls } }
    var focusedDisplayCalls: Int { state.withLock { $0.focusedDisplayCalls } }
    var focusCalls: [DisplayID] { state.withLock { $0.focusCalls } }
    /// The layout each `focus` call was given.
    var focusLayouts: [DisplayLayout] { state.withLock { $0.layouts } }
    var focusCancelled: [Bool] { state.withLock { $0.focusCancelled } }
    /// True while a held `focus` call is waiting to be released.
    var isHoldingFocus: Bool { state.withLock { $0.waiter != nil } }

    func setTrusted(_ value: Bool) {
        state.withLock { $0.trusted = value }
    }

    func setWindows(_ windows: [DisplayID: WindowSummary]) {
        state.withLock { $0.windows = windows }
    }

    func setFocusedDisplay(_ display: DisplayID?) {
        state.withLock { $0.focusedDisplay = display }
    }

    func setResult(_ result: FocusResult) {
        state.withLock { $0.result = result }
    }

    /// Makes `focus` wait until `release()`.
    func holdFocusRequests() {
        state.withLock {
            $0.holdsFocus = true
            $0.released = false
        }
    }

    func release() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func isTrusted() -> Bool {
        state.withLock {
            $0.isTrustedCalls += 1
            return $0.trusted
        }
    }

    func requestTrust() {
        state.withLock { $0.requestTrustCalls += 1 }
    }

    func lastUsedWindows(in layout: DisplayLayout) async -> [DisplayID: WindowSummary] {
        state.withLock {
            $0.lastUsedWindowsCalls += 1
            return $0.windows
        }
    }

    func focusedDisplay(in layout: DisplayLayout) async -> DisplayID? {
        state.withLock {
            $0.focusedDisplayCalls += 1
            return $0.focusedDisplay
        }
    }

    func focus(display: DisplayID, in layout: DisplayLayout) async -> FocusResult {
        let shouldHold = state.withLock { state -> Bool in
            state.focusCalls.append(display)
            state.layouts.append(layout)
            return state.holdsFocus && !state.released
        }
        if shouldHold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.released { return true }
                    state.waiter = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        let cancelled = Task.isCancelled
        return state.withLock {
            $0.focusCancelled.append(cancelled)
            return $0.result
        }
    }
}
