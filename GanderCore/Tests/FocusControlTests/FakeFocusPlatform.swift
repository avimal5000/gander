import CoreGraphics
import Foundation
import GanderModels
import os

@testable import FocusControl

/// A scripted stand-in for the system. It records every call and decides, from the call history, when the
/// target window counts as focused. It never touches a real window.
final class FakeFocusPlatform: FocusPlatform {
    enum Call: Equatable {
        case prepare
        case raise
        case activate(Int32)
        case frontmost
        case check
    }

    /// When the fake reports focus.
    enum FocusRule: Sendable {
        /// Never.
        case never
        /// From the n-th check onward (1-based) after the first raise.
        case onCheck(Int)
        /// From the first check after an activation request.
        case afterActivation
        /// From the first check after the app was made frontmost through Accessibility: an app that ignores
        /// activation.
        case afterFrontmost
    }

    private struct State {
        var calls: [Call] = []
        var checksSinceFirstRaise = 0
        var activated = false
        var madeFrontmost = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let handle: Int?
    private let windowTitle: String?
    private let rule: FocusRule

    init(handle: Int? = 1, title: String? = nil, rule: FocusRule) {
        self.handle = handle
        self.windowTitle = title
        self.rule = rule
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func prepare(_ target: WindowSummary) async -> Int? {
        state.withLock { $0.calls.append(.prepare) }
        return handle
    }

    func title(of handle: Int) -> String? {
        windowTitle
    }

    func raise(_ handle: Int) async {
        state.withLock { $0.calls.append(.raise) }
    }

    func activateApplication(processID: Int32) async {
        state.withLock {
            $0.calls.append(.activate(processID))
            $0.activated = true
        }
    }

    func makeFrontmost(_ handle: Int) async {
        state.withLock {
            $0.calls.append(.frontmost)
            $0.madeFrontmost = true
        }
    }

    func isFocused(_ handle: Int) async -> Bool {
        let rule = rule
        return state.withLock { state in
            state.calls.append(.check)
            state.checksSinceFirstRaise += 1
            switch rule {
            case .never: return false
            case .onCheck(let n): return state.checksSinceFirstRaise >= n
            case .afterActivation: return state.activated
            case .afterFrontmost: return state.madeFrontmost
            }
        }
    }
}
