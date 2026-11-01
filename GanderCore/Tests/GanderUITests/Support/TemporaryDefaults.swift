import Foundation

/// A defaults suite kept under the temporary directory (`Harness.temporarySuiteName()`), so a test never leaves a
/// file in `~/Library/Preferences`. Call `remove()` when the test ends.
struct TemporaryDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = Harness.temporarySuiteName()
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("Cannot create test defaults") }
        self.defaults = defaults
    }

    /// Clears the suite and deletes its file.
    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }
}
