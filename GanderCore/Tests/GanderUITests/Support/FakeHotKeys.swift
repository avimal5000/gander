import Foundation
import GanderModels

/// A hot key registry that never touches Carbon. Like the real center, `register` first drops the action's current
/// shortcut, so a failed registration leaves the action without one.
@MainActor
final class FakeHotKeys: HotKeyRegistering {
    /// The shortcut each action has right now.
    private(set) var registered: [HotKeyAction: HotKeyShortcut] = [:]
    private(set) var registerCalls: [HotKeyShortcut] = []
    private(set) var unregisterCalls: [HotKeyAction] = []
    private var handlers: [HotKeyAction: @MainActor () -> Void] = [:]
    /// Shortcuts that fail to register, with the error to throw.
    var failures: [(shortcut: HotKeyShortcut, error: HotKeyError)] = []

    func register(
        _ shortcut: HotKeyShortcut, for action: HotKeyAction, handler: @escaping @MainActor () -> Void
    ) throws(HotKeyError) {
        registerCalls.append(shortcut)
        registered[action] = nil
        handlers[action] = nil
        if let failure = failures.first(where: { $0.shortcut == shortcut }) { throw failure.error }
        registered[action] = shortcut
        handlers[action] = handler
    }

    func unregister(_ action: HotKeyAction) {
        unregisterCalls.append(action)
        registered[action] = nil
        handlers[action] = nil
    }

    /// Simulates the user pressing the action's shortcut.
    func press(_ action: HotKeyAction = .toggleFocusLock) {
        handlers[action]?()
    }
}
