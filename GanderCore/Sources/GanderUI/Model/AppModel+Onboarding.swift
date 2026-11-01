import Foundation

/// The first-run walkthrough: the Set Up window opens by itself the first time Gander runs.
extension AppModel {
    /// The rule: open on launch only when nothing is calibrated and the walkthrough has not shown before. People who
    /// already have calibrations (an update, or settings carried over from the earlier name) are not first-run.
    static func shouldAutoOpenOnboarding(libraryIsEmpty: Bool, seen: Bool) -> Bool {
        libraryIsEmpty && !seen
    }

    /// Asks for the Set Up window at launch when the rule says so, so the launch guard lets it show. Returns whether it
    /// did. The window's first appearance records that it was seen.
    @discardableResult
    public func requestOnboardingIfFirstRun() -> Bool {
        let seen = defaults.bool(forKey: DefaultsKey.onboardingSeen)
        guard Self.shouldAutoOpenOnboarding(libraryIsEmpty: library.profiles.isEmpty, seen: seen) else { return false }
        onboardingPending = true
        noteWindowRequested(GanderWindowID.setup)
        return true
    }
}
