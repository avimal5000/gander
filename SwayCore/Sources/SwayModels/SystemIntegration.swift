import Foundation

/// A global keyboard shortcut: a virtual key code plus modifiers (SPEC F17).
public struct HotKeyShortcut: Sendable, Equatable, Codable {
    /// Modifier keys, independent of any framework's flag values.
    public struct Modifiers: OptionSet, Sendable, Hashable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// macOS virtual key code (`kVK_ANSI_L` is 37).
    public let keyCode: UInt16
    public let modifiers: Modifiers
    /// What the key is called on screen: "L", "F5", "Space".
    public let keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// The default Focus Lock shortcut, ⌃⌥⌘L (SPEC D6).
    public static let focusLockDefault = HotKeyShortcut(
        keyCode: 37, modifiers: [.control, .option, .command], keyLabel: "L")

    /// True when the shortcut includes Control, Option, or Command, so ordinary typing (with or without Shift) can
    /// never trigger it, and the key has a label.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.control, .option, .command]) && !keyLabel.isEmpty
    }

    /// The modifier symbols in the macOS menu order (⌃⌥⇧⌘), then the key: "⌃⌥⌘L".
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21E7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        return text + keyLabel
    }
}

/// What a global shortcut does.
public enum HotKeyAction: String, Sendable, CaseIterable, Codable {
    case toggleFocusLock
}

/// Why a shortcut could not be registered.
public enum HotKeyError: Error, Sendable, Equatable {
    /// The shortcut has no Control, Option, or Command, or no key.
    case invalidShortcut
    /// Another app already registered the same shortcut.
    case shortcutInUse
    /// Any other registration failure, with the system status code.
    case registrationFailed(Int32)
}

/// Registers global shortcuts without any special permission (no event taps or monitors). Implemented by
/// `SystemIntegration.CarbonHotKeyCenter`.
@MainActor
public protocol HotKeyRegistering: AnyObject {
    /// Registers `shortcut` for `action`, replacing that action's previous shortcut. `handler` runs on the main actor
    /// each time the shortcut is pressed, whichever app is active. When this throws, the action has no shortcut.
    func register(
        _ shortcut: HotKeyShortcut, for action: HotKeyAction, handler: @escaping @MainActor () -> Void
    ) throws(HotKeyError)
    /// Removes the action's shortcut, if it has one.
    func unregister(_ action: HotKeyAction)
}

/// Whether Gander opens at login.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case disabled
    /// Registered, but the user must still allow it in System Settings > General > Login Items.
    case requiresApproval
    /// The system cannot register this copy of the app; the text says why.
    case unavailable(String)
}

/// Why changing the login item failed, in words for the user.
public struct LoginItemError: Error, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Opens Gander at login, as the system's own login item for the app. Implemented by
/// `SystemIntegration.MainAppLoginItem`.
@MainActor
public protocol LoginItemControlling: AnyObject {
    /// The current state, read fresh from the system.
    var status: LoginItemStatus { get }
    /// Registers or unregisters the app as a login item.
    func setEnabled(_ enabled: Bool) throws(LoginItemError)
    /// Opens System Settings > General > Login Items.
    func openSystemSettings()
}
