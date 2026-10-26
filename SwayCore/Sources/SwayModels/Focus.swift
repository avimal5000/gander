import CoreGraphics
import Foundation

/// A window from the window list. Owner and bounds need no permission; the title needs Accessibility.
public struct WindowSummary: Sendable, Equatable, Identifiable {
    /// `kCGWindowNumber`; unique while the window exists.
    public let id: UInt32
    public let processID: Int32
    /// `kCGWindowOwnerName`.
    public let appName: String
    /// From Accessibility when trusted, else `nil` (window-list titles would need Screen Recording).
    public let title: String?
    /// Quartz global coordinates in points: origin at the top-left of the main display, y grows downward.
    /// (`DisplayInfo.frame` uses AppKit's bottom-left origin; convert before comparing.)
    public let bounds: CGRect
    /// Display holding most of the window's area.
    public let displayID: DisplayID

    public init(id: UInt32, processID: Int32, appName: String, title: String?, bounds: CGRect, displayID: DisplayID) {
        self.id = id
        self.processID = processID
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.displayID = displayID
    }
}

/// Which step of the focus fallback list succeeded.
public enum FocusMethod: String, Sendable, Equatable, Codable {
    /// `AXRaise` and `AXMain` on the window, then `NSRunningApplication` activation of its app, which brings only the
    /// app's main and key windows forward (SPEC D42).
    case appActivation
    /// The fallback: `AXFrontmost` on the app, then the raise again. This can bring all of the app's windows forward.
    case accessibilityFrontmost
}

/// Outcome of a focus request.
public enum FocusResult: Sendable, Equatable {
    /// Verified: the window's app is frontmost and the window is its focused window.
    case focused(WindowSummary, method: FocusMethod, milliseconds: Int)
    /// No normal window on that display (or the display is not in the layout).
    case noWindow(DisplayID)
    /// Accessibility permission is missing; nothing was attempted.
    case notTrusted
    /// Every method was tried and verification failed, or the app did not answer in time.
    case failed(WindowSummary?, reason: String)
}

/// Finds the last-used window on each display and gives it keyboard focus without moving the cursor.
/// Implemented by `FocusControl.AXFocusController`.
public protocol FocusControlling: Sendable {
    /// Accessibility permission right now. Never prompts.
    func isTrusted() -> Bool
    /// Shows the system Accessibility prompt. The system shows it at most once per launch.
    func requestTrust()
    /// The last-used window on each display: its topmost normal window in z-order, excluding Sway's own windows.
    /// Displays without one are absent.
    func lastUsedWindows(in layout: DisplayLayout) async -> [DisplayID: WindowSummary]
    /// The display of the frontmost app's focused window (Sway's own windows excluded); `nil` if unknown.
    func focusedDisplay(in layout: DisplayLayout) async -> DisplayID?
    /// Raises and activates the last-used window on `display`, then verifies it. Never moves the cursor.
    func focus(display: DisplayID, in layout: DisplayLayout) async -> FocusResult
}
