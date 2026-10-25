import SwayModels

/// Shows the full-screen target overlay for the display the user should look at. A protocol so `AppModel` is
/// testable without real screens.
@MainActor
protocol GateOverlayPresenting: AnyObject {
    /// Called when the user presses Esc while the overlay is up.
    var onCancelRequested: (@MainActor () -> Void)? { get set }
    /// Whether the screen for `display` is connected right now.
    func canPresent(on display: DisplayInfo) -> Bool
    /// Shows or updates the overlay for `progress.display` and fades out overlays on every other screen.
    func present(_ progress: GateProgress)
    /// Fades out and removes every overlay and stops listening for Esc. Safe to call repeatedly.
    func dismiss()
}
