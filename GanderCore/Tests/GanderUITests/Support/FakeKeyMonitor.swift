import AppKit
import Foundation

@testable import GanderUI

/// A key monitor that never installs an `NSEvent` monitor. Tests send key presses with `press(_:)`.
@MainActor
final class FakeKeyMonitor: ShortcutKeyMonitoring {
    private(set) var isActive = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: (@MainActor (ShortcutKeyPress) -> Bool)?

    func start(_ handler: @escaping @MainActor (ShortcutKeyPress) -> Bool) {
        guard !isActive else { return }
        isActive = true
        startCount += 1
        self.handler = handler
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        stopCount += 1
        handler = nil
    }

    /// Simulates the user pressing a key. Returns whether the recorder consumed it; false when nothing listens.
    @discardableResult
    func press(
        _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = [], characters: String? = nil
    ) -> Bool {
        handler?(
            ShortcutKeyPress(keyCode: keyCode, modifierFlags: modifiers, charactersIgnoringModifiers: characters))
            ?? false
    }
}
