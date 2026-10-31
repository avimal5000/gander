/// Wording for the Set Up Gander window that more than one place needs (SPEC F20).
enum SetupPresentation {
    /// The welcome step (SPEC F26).
    static let welcomeTitle = "Welcome to Gander"
    static let welcomeLine = "Look at a display, and Gander moves your typing there. The pointer never moves."
    static let welcomePrivacy =
        "Your camera stays private. Gander reads only which way your head is turned, on this Mac. "
        + "Video is never recorded, saved, or sent anywhere."
    static let welcomeButton = "Get Started"
    /// The advice on the camera check.
    static let cameraAdvice =
        "Put the camera where it sees your face from every display. On top of the middle display works best."
    static let needsSecondDisplay = "Connect a second display to calibrate."
    static let calibrationCancelled = "Calibration cancelled."
    /// What skipping the Accessibility step leads to.
    static let skipConsequence =
        "If you skip, Gander shows Needs Accessibility and does not switch focus until you allow it."
}
