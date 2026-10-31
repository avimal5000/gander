import GanderModels

/// Global shortcuts through Carbon `RegisterEventHotKey` (CONTRACT 6.8). macOS delivers only the registered key
/// combination, so this needs no permission and watches no other keystrokes.
@MainActor
public final class CarbonHotKeyCenter: HotKeyRegistering {
    private let registry = CarbonHotKeyRegistry()
    private let logger = GanderLog.logger(category: "system")

    public init() {}

    deinit {
        registry.unregisterAll()
    }

    /// Registers `shortcut` for `action`, replacing the action's previous shortcut. Throws `.invalidShortcut` before
    /// touching Carbon, `.shortcutInUse` when another app owns the combination, and `.registrationFailed` for any
    /// other system status. On any failure the action has no shortcut.
    public func register(
        _ shortcut: HotKeyShortcut, for action: HotKeyAction, handler: @escaping @MainActor () -> Void
    ) throws(HotKeyError) {
        guard shortcut.isValid else {
            logger.error("Rejected invalid shortcut \(shortcut.displayString, privacy: .public)")
            throw .invalidShortcut
        }

        let status = registry.register(
            keyCode: UInt32(shortcut.keyCode),
            modifiers: CarbonHotKeyMapping.carbonModifiers(for: shortcut.modifiers),
            action: action,
            handler: handler)
        if let error = CarbonHotKeyMapping.error(forStatus: status) {
            logger.error(
                "Could not register \(shortcut.displayString, privacy: .public) (status \(status, privacy: .public))")
            throw error
        }
        logger.info("Registered global shortcut \(shortcut.displayString, privacy: .public)")
    }

    /// Removes the action's shortcut. Does nothing when it has none.
    public func unregister(_ action: HotKeyAction) {
        if registry.unregister(action) {
            logger.info("Removed the global shortcut for \(action.rawValue, privacy: .public)")
        }
    }
}
