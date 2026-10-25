import Foundation
import SwayModels

/// What the Focus Test window is doing. Only one focus request exists at a time: a pending countdown or a request
/// in flight blocks new presses.
enum FocusActivity: Equatable {
    case idle
    /// "Focus in 3 s" was pressed; focus fires when the model clock reaches `deadline` (monotonic seconds).
    case countingDown(display: DisplayID, deadline: TimeInterval)
    /// `FocusControlling.focus(display:in:)` is running for `display`.
    case focusing(display: DisplayID)
}
