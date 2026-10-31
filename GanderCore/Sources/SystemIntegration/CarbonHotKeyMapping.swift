// Carbon's hot key types (`EventHotKeyID`, the modifier masks, the status codes) are plain C values. The import is
// `@preconcurrency` because Carbon predates Swift concurrency and carries no Sendable annotations.
@preconcurrency import Carbon
import GanderModels

/// The pure translations between Gander's shortcut types and Carbon's hot key values. No Carbon call happens here, so
/// every function is safe to run in tests.
enum CarbonHotKeyMapping {
    /// The four-character signature every Gander hot key carries, so a stray Carbon event for another app's hot key is
    /// never mistaken for ours.
    static let signatureText = "GNDR"

    /// `signatureText` as a `FourCharCode` (`0x474E4452`).
    static let signature: FourCharCode = fourCharCode(signatureText)

    /// The big-endian `FourCharCode` for the first four ASCII characters of `text`.
    static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    /// Carbon's modifier flags (`controlKey`, `optionKey`, `shiftKey`, `cmdKey`) for `modifiers`.
    static func carbonModifiers(for modifiers: HotKeyShortcut.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    /// The numeric hot key ID for `action`: 1-based and fixed per case. The switch is exhaustive on purpose: a new
    /// `HotKeyAction` case must pick an ID here instead of silently shifting the existing ones.
    static func actionID(for action: HotKeyAction) -> UInt32 {
        switch action {
        case .toggleFocusLock: 1
        }
    }

    /// The Carbon hot key ID (signature plus action ID) registered for `action`.
    static func hotKeyID(for action: HotKeyAction) -> EventHotKeyID {
        EventHotKeyID(signature: signature, id: actionID(for: action))
    }

    /// The action behind a Carbon hot key ID, or nil when the signature isn't Gander's or the ID is unknown.
    static func action(for hotKeyID: EventHotKeyID) -> HotKeyAction? {
        guard hotKeyID.signature == signature else { return nil }
        return HotKeyAction.allCases.first { actionID(for: $0) == hotKeyID.id }
    }

    /// Nil for success (`noErr`), `.shortcutInUse` when another app owns the combination
    /// (`eventHotKeyExistsErr`), and `.registrationFailed` carrying the status for anything else.
    static func error(forStatus status: OSStatus) -> HotKeyError? {
        if status == OSStatus(noErr) { return nil }
        if status == OSStatus(eventHotKeyExistsErr) { return .shortcutInUse }
        return .registrationFailed(status)
    }
}
