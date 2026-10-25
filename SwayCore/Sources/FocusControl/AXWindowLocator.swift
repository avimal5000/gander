import ApplicationServices
import CoreGraphics
import Foundation

/// An Accessibility window matched to a window-list window, with the app it belongs to.
struct LocatedWindow: Sendable {
    let processID: Int32
    let app: AXElementBox
    let window: AXElementBox
    /// The AX title, `nil` when the window has none.
    let title: String?
}

/// Finds the Accessibility window that corresponds to a window-list window.
enum AXWindowLocator {
    /// Messaging timeout for read-only lookups (titles, focused display), in seconds.
    static let lookupTimeout: Float = 0.25
    /// Messaging timeout while focusing, in seconds.
    static let focusTimeout: Float = 0.5

    /// Matches by frame within 2 pt; if nothing matches and the app has exactly one window, uses that one.
    /// Blocking: call only from the controller's serial queue. `nil` when the app has no matching window or does
    /// not answer within `messagingTimeout`.
    static func locate(processID: Int32, bounds: CGRect, messagingTimeout: Float) -> LocatedWindow? {
        let app = AXUIElementCreateApplication(processID)
        _ = AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let windows = AXElementAccess.windows(of: app) else { return nil }

        var frames: [CGRect?] = []
        frames.reserveCapacity(windows.count)
        for window in windows {
            _ = AXUIElementSetMessagingTimeout(window, messagingTimeout)
            let reading = AXElementAccess.frame(of: window)
            if reading.timedOut { return nil }
            frames.append(reading.frame)
        }
        guard let index = AXFrameMatcher.selectedIndex(for: bounds, among: frames) else { return nil }

        let window = windows[index]
        return LocatedWindow(
            processID: processID,
            app: AXElementBox(element: app),
            window: AXElementBox(element: window),
            title: AXElementAccess.title(of: window)
        )
    }
}
