import AppKit
import Foundation
import SwayModels

/// One key-down seen while a shortcut is being recorded: the facts of an `NSEvent` the mapping needs.
struct ShortcutKeyPress: Equatable {
    var keyCode: UInt16
    var modifierFlags: NSEvent.ModifierFlags
    var charactersIgnoringModifiers: String?
}

/// What a key press means to the shortcut recorder.
enum ShortcutCapture: Equatable {
    /// Esc on its own: stop recording.
    case cancel
    /// Not usable as a shortcut (no Control, Option, or Command, or a key with no name).
    case invalid
    case shortcut(HotKeyShortcut)
}

/// Turns a key press into a `HotKeyShortcut` (SPEC F21). Pure, so it is unit tested without any events.
enum ShortcutMapping {
    /// Shown when a press cannot be a shortcut.
    static let invalidMessage = "Use Control, Option, or Command with a key."

    static let escapeKeyCode: UInt16 = 53

    /// Keys that have no printable character, by virtual key code.
    private static let namedKeys: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape", 76: "Enter", 114: "Help",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    /// The shortcut a press records. Esc without Control, Option, or Command cancels; any other press needs one of
    /// those three modifiers and a key with a name.
    static func capture(_ press: ShortcutKeyPress) -> ShortcutCapture {
        let modifiers = modifiers(from: press.modifierFlags)
        let hasRequiredModifier = !modifiers.isDisjoint(with: [.control, .option, .command])
        if press.keyCode == escapeKeyCode, !hasRequiredModifier { return .cancel }
        guard hasRequiredModifier,
            let label = keyLabel(keyCode: press.keyCode, characters: press.charactersIgnoringModifiers)
        else { return .invalid }
        return .shortcut(HotKeyShortcut(keyCode: press.keyCode, modifiers: modifiers, keyLabel: label))
    }

    /// The modifiers among `flags`, independent of AppKit's flag values.
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyShortcut.Modifiers {
        var result: HotKeyShortcut.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    /// What the key is called on screen: a name for Space, Return, Tab, Delete, Escape, the arrows, and F1 to F20;
    /// otherwise its uppercased character. `nil` for a key with neither.
    static func keyLabel(keyCode: UInt16, characters: String?) -> String? {
        if let name = namedKeys[keyCode] { return name }
        guard let characters, characters.count == 1, let scalar = characters.unicodeScalars.first,
            isPrintable(scalar)
        else { return nil }
        return characters.uppercased()
    }

    /// Letters, digits, and punctuation: not control characters, whitespace, or the private-use characters AppKit
    /// reports for function keys.
    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.controlCharacters.contains(scalar) { return false }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
        return !(0xF700...0xF8FF).contains(scalar.value)
    }
}
