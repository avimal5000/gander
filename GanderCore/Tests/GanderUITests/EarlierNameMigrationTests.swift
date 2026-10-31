import Foundation
import Testing

@testable import GanderUI

@Suite("Earlier name migration")
struct EarlierNameMigrationTests {
    private func freshDefaults() -> UserDefaults {
        let name = "gander.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func copiesEarlierKeysUnderTheNewPrefix() {
        let defaults = freshDefaults()
        let copied = EarlierNameMigration.run(
            in: defaults,
            earlierValues: ["sway.trackingEnabled": true, "sway.accentChoice": "sway", "other": 1]
        )
        #expect(copied == 2)
        #expect(defaults.bool(forKey: "gander.trackingEnabled"))
        #expect(defaults.string(forKey: "gander.accentChoice") == "gander")
        #expect(defaults.object(forKey: "other") == nil)
    }

    @Test func keepsValuesAlreadySetUnderTheNewName() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "gander.trackingEnabled")
        EarlierNameMigration.run(in: defaults, earlierValues: ["sway.trackingEnabled": true])
        #expect(!defaults.bool(forKey: "gander.trackingEnabled"))
    }

    @Test func runsOnlyOnce() {
        let defaults = freshDefaults()
        #expect(EarlierNameMigration.run(in: defaults, earlierValues: ["sway.edgeGlowEnabled": false]) == 1)
        defaults.removeObject(forKey: "gander.edgeGlowEnabled")
        #expect(EarlierNameMigration.run(in: defaults, earlierValues: ["sway.edgeGlowEnabled": false]) == 0)
        #expect(defaults.object(forKey: "gander.edgeGlowEnabled") == nil)
    }
}
