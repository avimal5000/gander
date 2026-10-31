import Foundation

/// Carries settings over from the app's earlier name (bundle identifier `com.avimal5000.sway`, keys `sway.*`).
///
/// Run once at launch before the model reads its defaults. It copies each earlier key to its `gander.` name unless the
/// new key already has a value, then records that it ran, so a later reset by the user is not undone.
public enum EarlierNameMigration {
    static let earlierDomain = "com.avimal5000.sway"
    static let earlierPrefix = "sway."
    static let doneKey = "gander.migratedFromEarlierName"

    /// - Parameters:
    ///   - defaults: the current app's defaults.
    ///   - earlierValues: the earlier app's saved values; the default reads its preferences domain.
    /// - Returns: the number of keys copied.
    @discardableResult
    public static func run(
        in defaults: UserDefaults = .standard,
        earlierValues: [String: Any]? = nil
    ) -> Int {
        guard !defaults.bool(forKey: doneKey) else { return 0 }
        defer { defaults.set(true, forKey: doneKey) }
        let earlier = earlierValues ?? UserDefaults.standard.persistentDomain(forName: earlierDomain) ?? [:]
        var copied = 0
        for (key, value) in earlier where key.hasPrefix(earlierPrefix) {
            let newKey = "gander." + key.dropFirst(earlierPrefix.count)
            guard defaults.object(forKey: newKey) == nil else { continue }
            // The accent was saved as "sway" when it meant the app's own green.
            defaults.set(value as? String == "sway" ? "gander" : value, forKey: newKey)
            copied += 1
        }
        return copied
    }
}
