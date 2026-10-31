import AppKit

/// Delivers Gander's own key-down events while a shortcut is being recorded. A protocol so tests never install a
/// real monitor.
@MainActor
protocol ShortcutKeyMonitoring: AnyObject {
    /// True while the monitor is installed.
    var isActive: Bool { get }
    /// Starts delivering key-downs to `handler`, which returns true when it consumed the press (so the rest of the app
    /// never sees it). Does nothing if already started.
    func start(_ handler: @escaping @MainActor (ShortcutKeyPress) -> Bool)
    /// Stops delivering and removes the monitor. Does nothing if not started.
    func stop()
}

/// A local monitor: it only sees events delivered to Gander's own windows, needs no permission, and exists only while
/// a shortcut is being recorded.
@MainActor
final class LocalShortcutKeyMonitor: ShortcutKeyMonitoring {
    private var token: Any?

    var isActive: Bool { token != nil }

    func start(_ handler: @escaping @MainActor (ShortcutKeyPress) -> Bool) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let press = ShortcutKeyPress(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            )
            let consumed = MainActor.assumeIsolated { handler(press) }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
