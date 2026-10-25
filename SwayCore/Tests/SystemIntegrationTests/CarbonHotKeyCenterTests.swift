import SwayModels
import Testing

@testable import SystemIntegration

/// Only paths that never reach Carbon: registering a real hot key would capture that combination system-wide while
/// the tests run (CONTRACT 12).
@Suite @MainActor struct CarbonHotKeyCenterTests {
    nonisolated private static let invalidShortcuts: [HotKeyShortcut] = [
        HotKeyShortcut(keyCode: 37, modifiers: [], keyLabel: "L"),
        HotKeyShortcut(keyCode: 37, modifiers: [.shift], keyLabel: "L"),
        HotKeyShortcut(keyCode: 37, modifiers: [.control, .option, .command], keyLabel: ""),
    ]

    @Test(arguments: invalidShortcuts)
    func rejectsInvalidShortcutsBeforeTouchingCarbon(shortcut: HotKeyShortcut) {
        let center = CarbonHotKeyCenter()
        var handlerRan = false
        do {
            try center.register(shortcut, for: .toggleFocusLock) { handlerRan = true }
            Issue.record("Expected .invalidShortcut for \(shortcut.displayString)")
        } catch {
            #expect(error == .invalidShortcut)
        }
        #expect(!handlerRan)
    }

    @Test func unregisteringAnUnregisteredActionIsANoOp() {
        let center = CarbonHotKeyCenter()
        center.unregister(.toggleFocusLock)
        center.unregister(.toggleFocusLock)
    }

    @Test func unregisteringAfterARejectedShortcutIsANoOp() {
        let center = CarbonHotKeyCenter()
        _ = try? center.register(HotKeyShortcut(keyCode: 37, modifiers: [], keyLabel: "L"), for: .toggleFocusLock) {}
        center.unregister(.toggleFocusLock)
    }
}
