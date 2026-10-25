import SwayModels

/// What the focus sequence needs from the system. `LiveFocusPlatform` uses Accessibility and AppKit; tests
/// supply a fake, so the fallback logic runs without touching real windows.
protocol FocusPlatform: Sendable {
    /// Whatever identifies the target window in later calls (an Accessibility window in the live platform).
    associatedtype Handle: Sendable

    /// Finds the target's Accessibility window. `nil` when it cannot be found or the app does not answer.
    func prepare(_ target: WindowSummary) async -> Handle?
    /// The window's title as Accessibility reports it, if any.
    func title(of handle: Handle) -> String?
    /// Raises the window, makes it the app's main window, and makes its app frontmost.
    func raise(_ handle: Handle) async
    /// Asks the system to activate the app with this process ID.
    func activateApplication(processID: Int32) async
    /// True when the window's app is frontmost and the window is its focused window.
    func isFocused(_ handle: Handle) async -> Bool
}
