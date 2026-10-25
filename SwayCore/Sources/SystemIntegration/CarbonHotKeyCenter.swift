import SwayModels

/// Global shortcuts through Carbon `RegisterEventHotKey` (CONTRACT 6.8). Orchestrator stub: builder-system replaces it.
@MainActor
public final class CarbonHotKeyCenter: HotKeyRegistering {
    public init() {}

    public func register(
        _ shortcut: HotKeyShortcut, for action: HotKeyAction, handler: @escaping @MainActor () -> Void
    ) throws(HotKeyError) {
        throw .registrationFailed(-1)
    }

    public func unregister(_ action: HotKeyAction) {}
}
