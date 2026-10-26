import Foundation
import SwayModels

// Focus Lock and its global shortcut (SPEC F17, D27). While Focus Lock is on the camera stays on and nothing switches.
// The shortcut is registered through the injected `HotKeyRegistering` (a Carbon hot key in the app: no permission, no
// event tap), so it works from any app.
extension AppModel {
    // MARK: Focus Lock

    /// Turns Focus Lock on or off (the menu switch). Not saved: Focus Lock is off at launch.
    func setFocusLock(_ locked: Bool) {
        guard locked != focusLocked else { return }
        focusLocked = locked
        SwayLogger.tracking.info("Focus Lock \(locked ? "on" : "off", privacy: .public)")
    }

    /// Toggles Focus Lock, without any notice.
    func toggleFocusLock() {
        setFocusLock(!focusLocked)
    }

    /// The shortcut's action: toggles Focus Lock and tells the user on the focused display (SPEC F28). The menu switch
    /// goes through ``setFocusLock(_:)`` instead and shows nothing, because the change is in front of the user.
    func focusLockShortcutPressed() {
        toggleFocusLock()
        showFocusLockNotice()
    }

    // MARK: Shortcut

    /// Registers the saved shortcut (or the default) at launch. A failure is kept as `shortcutMessage`.
    func registerFocusLockShortcut() {
        guard let shortcut = focusLockShortcut else { return }
        do {
            try hotKeys.register(shortcut, for: .toggleFocusLock) { [weak self] in
                self?.focusLockShortcutPressed()
            }
            shortcutMessage = nil
            isShortcutRegistered = true
        } catch {
            shortcutMessage = Self.shortcutMessage(for: error, shortcut: shortcut)
            isShortcutRegistered = false
            SwayLogger.tracking.info("The Focus Lock shortcut could not be registered")
        }
    }

    /// The menu warns only while the chosen shortcut doesn't work. A refused change in Settings, with the previous
    /// shortcut registered again, is told in Settings alone.
    var menuShortcutMessage: String? {
        focusLockShortcut != nil && !isShortcutRegistered ? shortcutMessage : nil
    }

    /// Replaces the Focus Lock shortcut (`nil` removes it). The new one is registered first; on success it is saved
    /// and the message cleared. On failure the previous shortcut stays registered, nothing is saved, and the message
    /// says why.
    /// - Returns: whether the new shortcut is now in effect.
    @discardableResult
    func setFocusLockShortcut(_ shortcut: HotKeyShortcut?) -> Bool {
        let previous = focusLockShortcut
        guard let shortcut else {
            hotKeys.unregister(.toggleFocusLock)
            saveFocusLockShortcut(nil)
            focusLockShortcut = nil
            shortcutMessage = nil
            isShortcutRegistered = false
            return true
        }
        do {
            try hotKeys.register(shortcut, for: .toggleFocusLock) { [weak self] in
                self?.focusLockShortcutPressed()
            }
        } catch {
            shortcutMessage = Self.shortcutMessage(for: error, shortcut: shortcut)
            isShortcutRegistered = restore(previous)
            return false
        }
        saveFocusLockShortcut(shortcut)
        focusLockShortcut = shortcut
        shortcutMessage = nil
        isShortcutRegistered = true
        return true
    }

    /// A failed registration leaves the action without a shortcut, so register the previous one again.
    /// - Returns: whether the previous shortcut is registered again.
    private func restore(_ previous: HotKeyShortcut?) -> Bool {
        guard let previous else { return false }
        do {
            try hotKeys.register(previous, for: .toggleFocusLock) { [weak self] in
                self?.focusLockShortcutPressed()
            }
            return true
        } catch {
            return false
        }
    }

    private func saveFocusLockShortcut(_ shortcut: HotKeyShortcut?) {
        guard let shortcut else {
            // An empty value means "no shortcut", as opposed to an absent key, which means the default.
            defaults.set(Data(), forKey: DefaultsKey.focusLockShortcut)
            return
        }
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: DefaultsKey.focusLockShortcut)
        }
    }

    /// The saved shortcut: an absent key means the default, an empty value means none, otherwise the stored one
    /// (the default if it does not decode).
    static func storedFocusLockShortcut(in defaults: UserDefaults) -> HotKeyShortcut? {
        guard let data = defaults.data(forKey: DefaultsKey.focusLockShortcut) else { return .focusLockDefault }
        if data.isEmpty { return nil }
        return (try? JSONDecoder().decode(HotKeyShortcut.self, from: data)) ?? .focusLockDefault
    }

    /// The words for a registration failure.
    static func shortcutMessage(for error: HotKeyError, shortcut: HotKeyShortcut) -> String {
        if error == .shortcutInUse {
            return "\(shortcut.displayString) is already used by another app. Choose another shortcut in Settings."
        }
        return "The Focus Lock shortcut could not be set up."
    }
}
