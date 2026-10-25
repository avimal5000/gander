/// Wording for the Set Up Sway window that more than one place needs (SPEC F20).
enum SetupPresentation {
    /// The advice on the camera check.
    static let cameraAdvice =
        "Put the camera where it sees your face from every display. On top of the middle display works best."
    static let needsSecondDisplay = "Connect a second display to calibrate."
    static let calibrationCancelled = "Calibration cancelled."
    /// What skipping the Accessibility step leads to.
    static let skipConsequence =
        "If you skip, Sway shows Needs Accessibility and does not switch focus until you allow it."
}
