import AppKit

/// Calls `onEscape` when Esc is pressed while one of Gander's own windows (the gate window) is key.
///
/// This is a local monitor: it only sees events delivered to this app, which needs no extra permission. The
/// overlay panels never take key status, so the gate window stays key and keeps receiving the keystroke.
@MainActor
final class EscapeKeyMonitor {
    /// Virtual key code of the Escape key.
    static let escapeKeyCode: UInt16 = 53

    private var token: Any?

    /// True while the monitor is installed.
    var isInstalled: Bool { token != nil }

    /// Installs the monitor; does nothing if already installed.
    func install(onEscape: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil
        }
    }

    /// Removes the monitor; does nothing if not installed.
    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
