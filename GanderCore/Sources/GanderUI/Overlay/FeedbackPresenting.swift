import GanderModels

/// Shows the two small pieces of feedback on a display: the edge glow after a switch (SPEC F27) and the Focus Lock
/// notice (SPEC F28). A protocol so `AppModel` is testable without real screens or panels.
///
/// Both are click-through and never take focus. `animated` is false when the system asks for Reduce Motion: the glow
/// or notice then just appears and disappears.
@MainActor
protocol FeedbackPresenting: AnyObject {
    /// Flashes a thin green border around `display`. A glow already showing restarts on the new display.
    func showGlow(on display: DisplayInfo, animated: Bool)
    /// Shows a small notice with an SF Symbol and `text` near the top of `display`. One already showing is replaced.
    func showNotice(_ text: String, symbol: String, on display: DisplayInfo, animated: Bool)
}
