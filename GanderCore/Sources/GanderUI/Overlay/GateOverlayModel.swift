import Observation

/// Drives one overlay panel's SwiftUI content. Updated at the gate timer's rate; the fade is a SwiftUI animation
/// on `isVisible`.
@MainActor
@Observable
final class GateOverlayModel {
    /// Latest progress for the target display.
    var progress: GateProgress
    /// False while faded out (before fade-in and during fade-out).
    var isVisible = false

    init(progress: GateProgress) {
        self.progress = progress
    }
}
