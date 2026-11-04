import CoreGraphics
import GanderModels

/// Decides whether focus that moved away from the switch's target must be put back (SPEC D54).
enum KeepFocusCheck {
    /// True when the app's focused window is assigned to a display other than `targetDisplay`: the case that made
    /// Gander switch straight back. A frame that is unknown or on no display says nothing, so it counts as false.
    static func focusLeftDisplay(
        _ targetDisplay: DisplayID,
        focusedFrame: CGRect?,
        displays: [QuartzDisplayFrame]
    ) -> Bool {
        guard let focusedFrame, let display = DisplayGeometry.assignedDisplay(for: focusedFrame, in: displays) else {
            return false
        }
        return display != targetDisplay
    }
}
