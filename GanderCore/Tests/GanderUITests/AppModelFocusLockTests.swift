import Foundation
import GanderModels
import Testing

@testable import GanderUI

@MainActor
@Suite("AppModel Focus Lock and its shortcut")
struct AppModelFocusLockTests {
    private let shortcutKey = "gander.focusLockShortcut"

    private let other = HotKeyShortcut(keyCode: 40, modifiers: [.control, .option], keyLabel: "K")
    private let another = HotKeyShortcut(keyCode: 38, modifiers: [.command, .shift], keyLabel: "J")

    private func storedShortcut(_ h: Harness) -> HotKeyShortcut? {
        guard let data = h.defaults.data(forKey: shortcutKey), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(HotKeyShortcut.self, from: data)
    }

    // MARK: The lock

    @Test func focusLockIsOffAtLaunchAndTogglesBothWays() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(!h.model.focusLocked)

        h.model.toggleFocusLock()
        #expect(h.model.focusLocked)
        h.model.toggleFocusLock()
        #expect(!h.model.focusLocked)

        h.model.setFocusLock(true)
        h.model.setFocusLock(true)
        #expect(h.model.focusLocked)
    }

    @Test func focusLockIsNotSaved() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.setFocusLock(true)

        #expect(!h.relaunchedModel().focusLocked)
    }

    @Test func focusLockShowsInTheStatusAndKeepsTheCameraOn() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        h.feed()
        #expect(h.model.trackingStatus == .tracking)

        h.model.setFocusLock(true)

        #expect(h.model.trackingStatus == .focusLock)
        #expect(h.model.menuBarSymbol == "lock.fill")
        #expect(h.model.statusLine == "Focus Lock on \u{00B7} FaceTime HD Camera")
        #expect(h.model.isCameraActive)
    }

    @Test func theDeciderIsToldTheLockIsOn() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()

        h.model.handle(.sample(Fixtures.sample(at: 1)))
        h.model.setFocusLock(true)
        h.model.handle(.sample(Fixtures.sample(at: 1.1)))

        #expect(h.engine.lastRecorder?.contexts.map(\.isFocusLocked) == [false, true])
    }

    // MARK: Shortcut at launch

    @Test func theDefaultShortcutIsRegisteredAtLaunchAndPressingItTogglesTheLock() {
        let h = Harness.make()
        defer { h.tearDown() }

        #expect(h.model.focusLockShortcut == .focusLockDefault)
        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(h.model.shortcutMessage == nil)

        h.hotKeys.press()
        #expect(h.model.focusLocked)
        h.hotKeys.press()
        #expect(!h.model.focusLocked)
    }

    @Test func aSavedShortcutIsRestoredAndRegistered() {
        let first = Harness.make()
        defer { first.tearDown() }
        #expect(first.model.setFocusLockShortcut(other))

        let hotKeys = FakeHotKeys()
        let relaunched = first.relaunchedModel(hotKeys: hotKeys)

        #expect(relaunched.focusLockShortcut == other)
        #expect(hotKeys.registered[.toggleFocusLock] == other)
    }

    @Test func aSavedClearMeansNoShortcutNotTheDefault() {
        let first = Harness.make()
        defer { first.tearDown() }
        #expect(first.model.setFocusLockShortcut(nil))
        #expect(first.defaults.data(forKey: shortcutKey) == Data())

        let hotKeys = FakeHotKeys()
        let relaunched = first.relaunchedModel(hotKeys: hotKeys)

        #expect(relaunched.focusLockShortcut == nil)
        #expect(hotKeys.registered.isEmpty)
        #expect(hotKeys.registerCalls.isEmpty)
    }

    @Test func aShortcutThatDoesNotDecodeFallsBackToTheDefault() {
        let h = Harness.make { $0.set(Data("not json".utf8), forKey: "gander.focusLockShortcut") }
        defer { h.tearDown() }

        #expect(h.model.focusLockShortcut == .focusLockDefault)
    }

    // MARK: Registration failures

    @Test func aShortcutAnotherAppHasShowsThatMessageAndNamesTheShortcut() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(HotKeyShortcut.focusLockDefault, .shortcutInUse)]
        let h = Harness.make(calibrated: true, hotKeys: hotKeys)
        defer { h.tearDown() }

        #expect(
            h.model.shortcutMessage
                == "\u{2303}\u{2325}\u{2318}L is already used by another app. Choose another shortcut in Settings.")
        #expect(hotKeys.registered.isEmpty)
        #expect(h.model.focusLockShortcut == .focusLockDefault, "Still the chosen shortcut, just not working")
        #expect(h.model.menuBanner == .shortcut(h.model.shortcutMessage ?? ""))
    }

    @Test func anyOtherFailureSaysTheShortcutCouldNotBeSetUp() {
        for error in [HotKeyError.registrationFailed(-9878), .invalidShortcut] {
            let hotKeys = FakeHotKeys()
            hotKeys.failures = [(HotKeyShortcut.focusLockDefault, error)]
            let h = Harness.make(hotKeys: hotKeys)
            defer { h.tearDown() }

            #expect(h.model.shortcutMessage == "The Focus Lock shortcut could not be set up.")
        }
    }

    // MARK: Changing the shortcut (used by Settings in M5)

    @Test func aNewShortcutIsRegisteredSavedAndClearsTheMessage() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(HotKeyShortcut.focusLockDefault, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        #expect(h.model.shortcutMessage != nil)

        let accepted = h.model.setFocusLockShortcut(other)

        #expect(accepted)
        #expect(h.model.focusLockShortcut == other)
        #expect(hotKeys.registered[.toggleFocusLock] == other)
        #expect(storedShortcut(h) == other)
        #expect(h.model.shortcutMessage == nil)
        hotKeys.press()
        #expect(h.model.focusLocked, "The new shortcut works")
    }

    @Test func aFailedChangeKeepsThePreviousShortcutRegisteredAndSaved() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(other, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        #expect(h.model.setFocusLockShortcut(another))

        let accepted = h.model.setFocusLockShortcut(other)

        #expect(!accepted)
        #expect(h.model.focusLockShortcut == another)
        #expect(hotKeys.registered[.toggleFocusLock] == another, "The old shortcut is registered again")
        #expect(storedShortcut(h) == another)
        #expect(h.model.shortcutMessage?.contains("already used by another app") == true)
        #expect(h.model.menuBanner != .shortcut(h.model.shortcutMessage ?? ""), "Settings says it; the menu needn't")
        hotKeys.press()
        #expect(h.model.focusLocked, "The old shortcut still works")
    }

    @Test func aFailedChangeWhenTheUserHadNoShortcutLeavesNone() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(other, .registrationFailed(-1))]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }
        #expect(h.model.setFocusLockShortcut(nil))

        #expect(!h.model.setFocusLockShortcut(other))

        #expect(h.model.focusLockShortcut == nil)
        #expect(hotKeys.registered.isEmpty)
        #expect(h.model.shortcutMessage == "The Focus Lock shortcut could not be set up.")
        #expect(h.model.menuShortcutMessage == nil, "The user chose no shortcut, so the menu has nothing to warn about")
    }

    @Test func clearingRemovesTheShortcutAndTheMessage() {
        let hotKeys = FakeHotKeys()
        hotKeys.failures = [(HotKeyShortcut.focusLockDefault, .shortcutInUse)]
        let h = Harness.make(hotKeys: hotKeys)
        defer { h.tearDown() }

        #expect(h.model.setFocusLockShortcut(nil))

        #expect(h.model.focusLockShortcut == nil)
        #expect(hotKeys.unregisterCalls == [.toggleFocusLock])
        #expect(h.model.shortcutMessage == nil)
        #expect(storedShortcut(h) == nil)
        #expect(h.defaults.data(forKey: shortcutKey) == Data())
    }

    @Test func resettingToTheDefaultRegistersItAgain() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.model.setFocusLockShortcut(other))

        #expect(h.model.setFocusLockShortcut(.focusLockDefault))

        #expect(h.hotKeys.registered[.toggleFocusLock] == .focusLockDefault)
        #expect(storedShortcut(h) == .focusLockDefault)
    }

    @Test func theShortcutsRegisteredCountsMatchTheCalls() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(h.hotKeys.registerCalls == [.focusLockDefault], "Once at launch, nothing else")
    }
}
