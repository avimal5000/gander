import Foundation
import Testing

@testable import GanderUI

@Suite("Earlier name migration")
final class EarlierNameMigrationTests {
    /// A fresh suite per test (Swift Testing makes a new instance for each), deleted when the test ends.
    private let store = TemporaryDefaults()

    deinit { store.remove() }

    @Test func copiesEarlierKeysUnderTheNewPrefix() {
        let defaults = store.defaults
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
        let defaults = store.defaults
        defaults.set(false, forKey: "gander.trackingEnabled")
        EarlierNameMigration.run(in: defaults, earlierValues: ["sway.trackingEnabled": true])
        #expect(!defaults.bool(forKey: "gander.trackingEnabled"))
    }

    @Test func runsOnlyOnce() {
        let defaults = store.defaults
        #expect(EarlierNameMigration.run(in: defaults, earlierValues: ["sway.edgeGlowEnabled": false]) == 1)
        defaults.removeObject(forKey: "gander.edgeGlowEnabled")
        #expect(EarlierNameMigration.run(in: defaults, earlierValues: ["sway.edgeGlowEnabled": false]) == 0)
        #expect(defaults.object(forKey: "gander.edgeGlowEnabled") == nil)
    }
}
