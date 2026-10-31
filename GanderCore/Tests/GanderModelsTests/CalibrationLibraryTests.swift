import CoreGraphics
import Foundation
import Testing

@testable import GanderModels

private func display(_ id: String, x: CGFloat) -> DisplayInfo {
    DisplayInfo(
        id: DisplayID(id), cgDisplayID: 1, name: id, frame: CGRect(x: x, y: 0, width: 1000, height: 600),
        isBuiltIn: false, isMain: false)
}

private func layout(_ ids: [String]) -> DisplayLayout {
    DisplayLayout(displays: ids.enumerated().map { display($0.element, x: CGFloat($0.offset) * 1000) })
}

private func profile(
    _ ids: [String], camera: String? = "C922", created: TimeInterval = 0, formatVersion: Int = 1
) -> CalibrationProfile {
    CalibrationProfile(
        formatVersion: formatVersion,
        features: .visionAngles,
        displays: ids.enumerated().map {
            DisplayProfile(
                displayID: DisplayID($0.element), yaw: Double($0.offset) * 20, pitch: 5, yawStd: 1, pitchStd: 2,
                sampleCount: 60)
        },
        yawScale: 1.5,
        pitchScale: 2.5,
        layoutFingerprint: layout(ids).fingerprint,
        cameraName: camera,
        createdAt: Date(timeIntervalSince1970: created)
    )
}

@Suite("Calibration library")
struct CalibrationLibraryTests {
    @Test func keyIgnoresDisplayOrder() {
        #expect(profile(["A", "B"]).key == profile(["B", "A"]).key)
        #expect(profile(["A", "B"]).key != profile(["A", "B"], camera: "FaceTime").key)
    }

    @Test func restrictedKeepsOrderScalesAndMetadata() {
        let full = profile(["A", "B", "C"])
        let restricted = full.restricted(to: ["C", "A"])
        #expect(restricted.displays.map(\.displayID) == ["A", "C"])
        #expect(restricted.yawScale == full.yawScale)
        #expect(restricted.pitchScale == full.pitchScale)
        #expect(restricted.cameraName == full.cameraName)
        #expect(restricted.createdAt == full.createdAt)
    }

    @Test func saveReplacesTheSameKeyAndPutsNewestFirst() {
        var library = CalibrationLibrary()
        library.save(profile(["A", "B"], created: 1))
        library.save(profile(["A", "B", "C"], created: 2))
        library.save(profile(["B", "A"], created: 3))
        #expect(library.profiles.map(\.createdAt.timeIntervalSince1970) == [3, 2])
    }

    @Test func saveIgnoresUnusableProfiles() {
        var library = CalibrationLibrary()
        library.save(profile(["A"]))
        library.save(profile(["A", "B"], formatVersion: 99))
        #expect(library.profiles.isEmpty)
    }

    @Test func saveTrimsToTheLimit() {
        var library = CalibrationLibrary()
        for index in 0..<(CalibrationLibrary.maxProfiles + 3) {
            library.save(profile(["A", "B"], camera: "Camera \(index)", created: Double(index)))
        }
        #expect(library.profiles.count == CalibrationLibrary.maxProfiles)
        #expect(library.profiles.first?.cameraName == "Camera \(CalibrationLibrary.maxProfiles + 2)")
        #expect(!library.profiles.contains { $0.cameraName == "Camera 0" })
    }

    @Test func removeDropsOnlyThatKey() {
        var library = CalibrationLibrary(profiles: [profile(["A", "B"]), profile(["A", "B", "C"])])
        library.remove(profile(["A", "B"]).key)
        #expect(library.profiles.map(\.key) == [profile(["A", "B", "C"]).key])
    }

    @Test func initKeepsTheGivenOrderNewestFirst() {
        let library = CalibrationLibrary(profiles: [profile(["A", "B"], created: 2), profile(["A", "C"], created: 1)])
        #expect(library.profiles.map(\.createdAt.timeIntervalSince1970) == [2, 1])
    }

    @Test func exactDisplaySetResolves() throws {
        let library = CalibrationLibrary(profiles: [profile(["A", "B"])])
        let match = try #require(library.resolve(for: layout(["A", "B"]), cameraName: "C922"))
        #expect(match.profile == match.saved)
        #expect(!match.isPartial)
    }

    @Test func aMovedDisplayStillResolves() {
        let library = CalibrationLibrary(profiles: [profile(["A", "B"])])
        let moved = DisplayLayout(displays: [display("A", x: 0), display("B", x: -1440)])
        #expect(library.resolve(for: moved, cameraName: "C922") != nil)
    }

    @Test func aSubsetOfALargerProfileResolvesRestricted() throws {
        let library = CalibrationLibrary(profiles: [profile(["A", "B", "C"])])
        let match = try #require(library.resolve(for: layout(["A", "C"]), cameraName: "C922"))
        #expect(match.profile.displays.map(\.displayID) == ["A", "C"])
        #expect(match.saved.displays.count == 3)
        #expect(match.isPartial)
    }

    @Test func theFewestExtraDisplaysWinThenTheMostRecentlySaved() throws {
        // Newest first: the ABE profile was saved after the ABC one.
        let library = CalibrationLibrary(profiles: [
            profile(["A", "B", "C", "D"], created: 5),
            profile(["A", "B", "E"], created: 9),
            profile(["A", "B", "C"], created: 1),
        ])
        let match = try #require(library.resolve(for: layout(["A", "B"]), cameraName: "C922"))
        #expect(match.saved.createdAt.timeIntervalSince1970 == 9)
        let exact = try #require(
            CalibrationLibrary(profiles: [profile(["A", "B", "C"], created: 9), profile(["A", "B"], created: 1)])
                .resolve(for: layout(["A", "B"]), cameraName: "C922"))
        #expect(!exact.isPartial)
    }

    @Test func unknownDisplaysOtherCamerasAndSingleDisplaysDoNotResolve() {
        let library = CalibrationLibrary(profiles: [profile(["A", "B"])])
        #expect(library.resolve(for: layout(["A", "B", "C"]), cameraName: "C922") == nil)
        #expect(library.resolve(for: layout(["A", "B"]), cameraName: "FaceTime HD Camera") == nil)
        #expect(library.resolve(for: layout(["A", "B"]), cameraName: nil) == nil)
        #expect(library.resolve(for: layout(["A"]), cameraName: "C922") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let library = CalibrationLibrary(profiles: [profile(["A", "B"], created: 2), profile(["A", "C"], created: 1)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationLibrary.self, from: try encoder.encode(library))
        #expect(decoded == library)
    }

    @Test func decodingDropsBrokenAndOutdatedProfiles() throws {
        let good = try JSONEncoder().encode(profile(["A", "B"]))
        let outdated = try JSONEncoder().encode(profile(["A", "C"], formatVersion: 7))
        let json = """
            {"formatVersion": 1, "profiles": [\(String(decoding: good, as: UTF8.self)), {"displays": 3}, \
            \(String(decoding: outdated, as: UTF8.self))]}
            """
        let library = try JSONDecoder().decode(CalibrationLibrary.self, from: Data(json.utf8))
        #expect(library.profiles.map(\.key) == [profile(["A", "B"]).key])
    }

    @Test func anotherLibraryVersionDecodesEmpty() throws {
        let json = #"{"formatVersion": 2, "profiles": []}"#
        #expect(try JSONDecoder().decode(CalibrationLibrary.self, from: Data(json.utf8)).profiles.isEmpty)
    }
}

@Suite("Switch sensitivity")
struct SwitchSensitivityTests {
    private func decoded(_ json: String) throws -> SwitchSensitivity {
        try JSONDecoder().decode(SwitchSensitivity.self, from: Data(json.utf8))
    }

    @Test func defaultsMatchTheEngineDefaults() {
        #expect(SwitchSensitivity.default.switchSettings() == .default)
        #expect(SwitchSensitivity.default == SwitchSensitivity(dwell: 0.40, cooldown: 0.75, confidenceLevel: 2))
    }

    @Test func mapsDwellAndMarginsKeepingTheRest() {
        let settings = SwitchSensitivity(dwell: 0.8, confidenceLevel: 4).switchSettings()
        #expect(settings.dwell == 0.8)
        #expect(settings.enterMargin == 0.45)
        #expect(settings.stayMargin == 0.225)
        #expect(settings.cooldown == SwitchSettings.default.cooldown)
        #expect(settings.maxGap == SwitchSettings.default.maxGap)
    }

    @Test func switchSettingsCarriesTheCooldownAndKeepsTheOtherFields() {
        let settings = SwitchSensitivity(dwell: 0.6, cooldown: 1.1, confidenceLevel: 1).switchSettings()
        #expect(settings.dwell == 0.6)
        #expect(settings.cooldown == 1.1)
        #expect(settings.enterMargin == 0.225)
        #expect(settings.stayMargin == 0.1125)
        #expect(settings.maxGap == SwitchSettings.default.maxGap)
        #expect(settings.minFaceConfidence == SwitchSettings.default.minFaceConfidence)
        #expect(settings.elsewhereYawMargin == SwitchSettings.default.elsewhereYawMargin)
        #expect(settings.elsewherePitchMargin == SwitchSettings.default.elsewherePitchMargin)
    }

    @Test func theRangesAreTheDocumentedOnes() {
        #expect(SwitchSensitivity.dwellRange == 0.05...1.5)
        #expect(SwitchSensitivity.cooldownRange == 0.2...1.5)
    }

    @Test func clampsEveryFieldIntoItsRange() {
        let low = SwitchSensitivity(dwell: 0, cooldown: 0, confidenceLevel: -3)
        #expect(low.dwell == SwitchSensitivity.dwellRange.lowerBound)
        #expect(low.cooldown == SwitchSensitivity.cooldownRange.lowerBound)
        #expect(low.confidenceLevel == 0)
        let high = SwitchSensitivity(dwell: 9, cooldown: 9, confidenceLevel: 40)
        #expect(high.dwell == SwitchSensitivity.dwellRange.upperBound)
        #expect(high.cooldown == SwitchSensitivity.cooldownRange.upperBound)
        #expect(high.confidenceLevel == SwitchSensitivity.confidenceMargins.count - 1)
        let inside = SwitchSensitivity(dwell: 0.05, cooldown: 0.2, confidenceLevel: 3)
        #expect(inside.dwell == 0.05)
        #expect(inside.cooldown == 0.2)
        #expect(inside.confidenceLevel == 3)
    }

    @Test func theOldInitializerKeepsTheDefaultCooldownAndClamps() {
        let old = SwitchSensitivity(dwell: 0.8, confidenceLevel: 4)
        #expect(old == SwitchSensitivity(dwell: 0.8, cooldown: 0.75, confidenceLevel: 4))
        #expect(SwitchSensitivity(dwell: 0, confidenceLevel: 9).dwell == SwitchSensitivity.dwellRange.lowerBound)
    }

    @Test func decodedOutOfRangeValuesAreClamped() throws {
        let value = try decoded(#"{"dwell": 7, "cooldown": 40, "confidenceLevel": 12}"#)
        #expect(value.dwell == SwitchSensitivity.dwellRange.upperBound)
        #expect(value.cooldown == SwitchSensitivity.cooldownRange.upperBound)
        #expect(value.confidenceLevel == SwitchSensitivity.confidenceMargins.count - 1)
        let settings = value.switchSettings()
        #expect(settings.dwell == SwitchSensitivity.dwellRange.upperBound)
        #expect(settings.cooldown == SwitchSensitivity.cooldownRange.upperBound)
        #expect(settings.enterMargin == SwitchSensitivity.confidenceMargins.last)

        let low = try decoded(#"{"dwell": -1, "cooldown": 0.01, "confidenceLevel": -5}"#)
        #expect(low.dwell == SwitchSensitivity.dwellRange.lowerBound)
        #expect(low.cooldown == SwitchSensitivity.cooldownRange.lowerBound)
        #expect(low.confidenceLevel == 0)
    }

    @Test func savedValuesWithoutACooldownDecodeWithTheDefaultOne() throws {
        let value = try decoded(#"{"dwell":0.2,"confidenceLevel":2}"#)
        #expect(value == SwitchSensitivity(dwell: 0.2, cooldown: 0.75, confidenceLevel: 2))
        #expect(value.switchSettings().cooldown == SwitchSettings.default.cooldown)
        #expect(try decoded(#"{"dwell":0.4,"confidenceLevel":2}"#) == .default)
    }

    @Test func aSavedValueMissingTheHoldTimeOrConfidenceStaysUnreadable() {
        #expect(throws: DecodingError.self) { try decoded(#"{"cooldown":0.5,"confidenceLevel":2}"#) }
        #expect(throws: DecodingError.self) { try decoded(#"{"dwell":0.4,"cooldown":0.5}"#) }
    }

    @Test func encodingWritesAllThreeValuesAndRoundTrips() throws {
        let value = SwitchSensitivity(dwell: 0.35, cooldown: 0.5, confidenceLevel: 3)
        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["dwell", "cooldown", "confidenceLevel"])
        #expect(object["dwell"] as? Double == 0.35)
        #expect(object["cooldown"] as? Double == 0.5)
        #expect(object["confidenceLevel"] as? Int == 3)
        #expect(try JSONDecoder().decode(SwitchSensitivity.self, from: data) == value)
        let defaultData = try JSONEncoder().encode(SwitchSensitivity.default)
        #expect(try JSONDecoder().decode(SwitchSensitivity.self, from: defaultData) == .default)
    }

    @Test func theInstantPresetIsAShortHoldAndPause() {
        #expect(SwitchSensitivity.instant.dwell == 0.10)
        #expect(SwitchSensitivity.instant.cooldown == 0.30)
        #expect(SwitchSensitivity.instant.dwell >= SwitchSensitivity.dwellRange.lowerBound)
        #expect(SwitchSensitivity.instant.cooldown >= SwitchSensitivity.cooldownRange.lowerBound)
        let settings = SwitchSensitivity.instant.switchSettings()
        #expect(settings.dwell == 0.10)
        #expect(settings.cooldown == 0.30)
    }

    @Test func applyingInstantTimingKeepsTheConfidence() {
        for level in 0..<SwitchSensitivity.confidenceMargins.count {
            let before = SwitchSensitivity(dwell: 1.2, cooldown: 1.4, confidenceLevel: level)
            let after = before.applyingInstantTiming()
            #expect(after.dwell == SwitchSensitivity.instant.dwell)
            #expect(after.cooldown == SwitchSensitivity.instant.cooldown)
            #expect(after.confidenceLevel == level)
        }
        #expect(SwitchSensitivity.default.applyingInstantTiming() == .instant)
        #expect(SwitchSensitivity.instant.applyingInstantTiming() == .instant)
    }
}

@Suite("Hot key shortcut")
struct HotKeyShortcutTests {
    @Test func defaultIsControlOptionCommandL() {
        let shortcut = HotKeyShortcut.focusLockDefault
        #expect(shortcut.keyCode == 37)
        #expect(shortcut.displayString == "\u{2303}\u{2325}\u{2318}L")
        #expect(shortcut.isValid)
    }

    @Test func displayStringUsesMenuOrder() {
        let shortcut = HotKeyShortcut(keyCode: 96, modifiers: [.command, .shift, .option, .control], keyLabel: "F5")
        #expect(shortcut.displayString == "\u{2303}\u{2325}\u{21E7}\u{2318}F5")
    }

    @Test func needsControlOptionOrCommandAndAKey() {
        #expect(!HotKeyShortcut(keyCode: 37, modifiers: [], keyLabel: "L").isValid)
        #expect(!HotKeyShortcut(keyCode: 37, modifiers: [.shift], keyLabel: "L").isValid)
        #expect(HotKeyShortcut(keyCode: 37, modifiers: [.option], keyLabel: "L").isValid)
        #expect(!HotKeyShortcut(keyCode: 37, modifiers: [.command], keyLabel: "").isValid)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(HotKeyShortcut.focusLockDefault)
        #expect(try JSONDecoder().decode(HotKeyShortcut.self, from: data) == .focusLockDefault)
    }
}
