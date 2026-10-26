import AppKit
import Foundation
import Observation
import SwayModels
import SwiftUI
import Testing
import os

@testable import SwayUI

@MainActor
@Suite("Appearance: accent, glow and notice settings")
struct AppearanceTests {
    private let accentKey = "sway.accentChoice"
    private let glowKey = "sway.edgeGlowEnabled"
    private let noticeKey = "sway.focusLockNoticeEnabled"

    // MARK: Sway green

    @Test func theBrandColorsAreUnchanged() {
        #expect(SwayPalette.forestHex == 0x2F5D3A)
        #expect(SwayPalette.sageHex == 0x9CAF88)
        #expect(SwayPalette.ivoryHex == 0xF6F3EA)
        #expect(SwayPalette.charcoalHex == 0x2B2B2B)
    }

    @Test func swayGreenIsForestInLightAndALighterGreenInDark() {
        #expect(SwayPalette.greenHex(isDark: false) == 0x2F5D3A)
        #expect(SwayPalette.greenHex(isDark: true) == 0x6FAF84)
    }

    @Test func theDynamicColorResolvesPerAppearance() throws {
        func components(in name: NSAppearance.Name) throws -> [Int] {
            let appearance = try #require(NSAppearance(named: name))
            let color = SwayPalette.makeGreen()
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
            let rgb = try #require(resolved)
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        #expect(try components(in: .aqua) == [0x2F, 0x5D, 0x3A])
        #expect(try components(in: .darkAqua) == [0x6F, 0xAF, 0x84])
    }

    // MARK: Accent choice

    @Test func swiftUIResolvesSwayGreenForEachColorScheme() throws {
        func hex(_ scheme: ColorScheme) throws -> UInt32 {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let color = try #require(
                SwayPalette.green.resolve(in: environment).cgColor.converted(
                    to: srgb, intent: .defaultIntent, options: nil))
            let parts = try #require(color.components).prefix(3).map { UInt32(($0 * 255).rounded()) }
            return parts[0] << 16 | parts[1] << 8 | parts[2]
        }
        #expect(try hex(.light) == SwayPalette.forestHex)
        #expect(try hex(.dark) == SwayPalette.greenDarkHex)
    }

    @Test func theAccentIsSwayGreenByDefault() {
        let h = Harness.make()
        defer { h.tearDown() }

        #expect(h.model.accentChoice == .sway)
        #expect(h.defaults.object(forKey: accentKey) == nil, "Nothing is written until the user chooses")
    }

    @Test func theTintIsSwayGreenOrTheSystemAccent() {
        #expect(AccentChoice.sway.tint == SwayPalette.green)
        #expect(AccentChoice.system.tint == nil, "No tint: SwiftUI keeps the system accent")
    }

    @Test func theChoicesHaveTheirSettingsLabelsAndSavedNames() {
        #expect(AccentChoice.allCases == [.sway, .system])
        #expect(AccentChoice.sway.title == "Sway green")
        #expect(AccentChoice.system.title == "Match macOS")
        #expect(AccentChoice.sway.rawValue == "sway")
        #expect(AccentChoice.system.rawValue == "system")
    }

    @Test func aChoiceIsAppliedAtOnceAndSaved() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.setAccentChoice(.system)
        #expect(h.model.accentChoice == .system)
        #expect(h.model.accentChoice.tint == nil)
        #expect(h.defaults.string(forKey: accentKey) == "system")

        h.model.setAccentChoice(.sway)
        #expect(h.model.accentChoice.tint == SwayPalette.green)
        #expect(h.defaults.string(forKey: accentKey) == "sway")
    }

    @Test func theChoiceSurvivesARelaunch() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.setAccentChoice(.system)

        #expect(h.relaunchedModel().accentChoice == .system)
    }

    @Test func anUnknownSavedChoiceMeansSwayGreen() {
        let h = Harness.make { $0.set("purple", forKey: "sway.accentChoice") }
        defer { h.tearDown() }

        #expect(h.model.accentChoice == .sway)
    }

    @Test func choosingTheSameAccentChangesNothing() {
        let h = Harness.make()
        defer { h.tearDown() }

        let changes = observedChanges({ h.model.accentChoice }) { h.model.setAccentChoice(.sway) }
        #expect(changes == 0)
        #expect(h.defaults.object(forKey: accentKey) == nil)
    }

    @Test func theAccentDoesNotChangeAtTheFrameRate() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        h.feed()
        #expect(h.model.menuBarGlyph == .tracking)

        let changes = observedChanges({ (h.model.accentChoice, h.model.edgeGlowEnabled, h.model.menuBarGlyph) }) {
            h.run(frames: 60, dt: 0.07)
        }
        #expect(changes == 0, "The root views read these, so they must not follow the samples")
    }

    // MARK: Glow and notice settings

    @Test func theGlowAndTheNoticeAreOnByDefault() {
        let h = Harness.make()
        defer { h.tearDown() }

        #expect(h.model.edgeGlowEnabled)
        #expect(h.model.focusLockNoticeEnabled)
        #expect(h.defaults.object(forKey: glowKey) == nil)
        #expect(h.defaults.object(forKey: noticeKey) == nil)
    }

    @Test func eachSwitchSavesAtOnceAndAppliesAtOnce() {
        let h = Harness.make()
        defer { h.tearDown() }

        h.model.setEdgeGlowEnabled(false)
        #expect(!h.model.edgeGlowEnabled)
        #expect(h.defaults.object(forKey: glowKey) as? Bool == false)
        #expect(h.model.focusLockNoticeEnabled, "The other one is unaffected")

        h.model.setFocusLockNoticeEnabled(false)
        #expect(!h.model.focusLockNoticeEnabled)
        #expect(h.defaults.object(forKey: noticeKey) as? Bool == false)

        h.model.setEdgeGlowEnabled(true)
        h.model.setFocusLockNoticeEnabled(true)
        #expect(h.model.edgeGlowEnabled && h.model.focusLockNoticeEnabled)
        #expect(h.defaults.object(forKey: glowKey) as? Bool == true)
        #expect(h.defaults.object(forKey: noticeKey) as? Bool == true)
    }

    @Test func bothSwitchesSurviveARelaunch() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.setEdgeGlowEnabled(false)

        let relaunched = h.relaunchedModel()
        #expect(!relaunched.edgeGlowEnabled)
        #expect(relaunched.focusLockNoticeEnabled)

        h.model.setFocusLockNoticeEnabled(false)
        #expect(!h.relaunchedModel().focusLockNoticeEnabled)
    }

    // MARK: Helpers

    private func observedChanges<T: Sendable>(
        _ read: @escaping @MainActor () -> T, during work: @MainActor () -> Void
    )
        -> Int
    {
        let count = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = read()
        } onChange: {
            count.withLock { $0 += 1 }
        }
        work()
        return count.withLock { $0 }
    }
}
