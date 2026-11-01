/// Wording for the Set Up Gander window that more than one place needs (SPEC F20).
enum SetupPresentation {
    /// The welcome step: the first-run intro, four pages.
    static let welcomeTitle = "Welcome to Gander"
    static let welcomeHeadline = "Look at a screen. Start typing."
    static let figureLabel = "Fig. 1"
    static let welcomeCaption = "Gander at work: the head turns, focus follows, the pointer stays."
    /// Spoken in place of the animated scene.
    static let welcomeSceneDescription =
        "Figure 1. Two monitors and a person seen from behind. The head turns right, the focus ring moves to the "
        + "right monitor, and the words ship it are typed there. The pointer stays where it was."

    static let stepsTitle = "Look. Settle. Type."
    static let steps = [
        "Gander watches your head turn",
        "You settle on another screen",
        "Focus follows your gaze; the pointer stays where it was",
    ]

    static let privacyTitle = "Your camera stays yours."
    static let privacyLines = [
        "Gander reads only which way your head is turned, on this Mac.",
        "No video or images are saved or sent.",
        "The camera light goes off when you pause.",
    ]
    static let privacyDescription = "A goose mark inside a padlock."

    static let menuBarTitle = "Find Gander in the menu bar"
    static let menuBarLine = "Click the goose to pause, lock or open Settings. Gander has no Dock icon."
    static let menuBarDescription = "A menu bar strip with the Gander goose, ringed by a gentle pulse."
    static let nextTitle = "What happens next"
    static let nextSteps = [
        "Allow the camera",
        "Allow Accessibility",
        "Look at each screen once",
    ]

    static let nextButton = "Next"
    static let backButton = "Back"
    static let skipButton = "Skip intro"
    /// The primary button on the last page.
    static let welcomeButton = "Set Up Gander"

    /// "Page 2 of 4", for the page dots as a whole.
    static func pageLabel(_ page: Int) -> String {
        "Page \(page + 1) of \(SetupFlow.introPageCount)"
    }

    /// The advice on the camera check.
    static let cameraAdvice =
        "Put the camera where it sees your face from every display. On top of the middle display works best."
    static let needsSecondDisplay = "Connect a second display to calibrate."
    static let calibrationCancelled = "Calibration cancelled."
    /// What skipping the Accessibility step leads to.
    static let skipConsequence =
        "If you skip, Gander shows Needs Accessibility and does not switch focus until you allow it."
}
