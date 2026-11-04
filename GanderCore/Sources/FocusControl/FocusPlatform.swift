import GanderModels

/// What the focus sequence needs from the system. `LiveFocusPlatform` uses Accessibility and AppKit; tests
/// supply a fake, so the fallback logic runs without touching real windows.
protocol FocusPlatform: Sendable {
    /// Whatever identifies the target window in later calls (an Accessibility window in the live platform).
    associatedtype Handle: Sendable

    /// Finds the target's Accessibility window. `nil` when it cannot be found or the app does not answer.
    func prepare(_ target: WindowSummary) async -> Handle?
    /// The window's title as Accessibility reports it, if any.
    func title(of handle: Handle) -> String?
    /// Raises the window and makes it the app's main window. Does not activate the app.
    func raise(_ handle: Handle) async
    /// Asks the system to activate the app with this process ID, bringing only its front window forward, or failing
    /// that its main and key windows.
    func activateApplication(processID: Int32) async
    /// Makes the window's app frontmost through Accessibility. This can bring all of the app's windows forward.
    func makeFrontmost(_ handle: Handle) async
    /// True when the window's app is frontmost and the window is its focused window.
    func isFocused(_ handle: Handle) async -> Bool
}
