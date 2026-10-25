import SwayModels

/// Opens Sway at login through `SMAppService.mainApp` (CONTRACT 6.8). Orchestrator stub: builder-system replaces it.
@MainActor
public final class MainAppLoginItem: LoginItemControlling {
    public init() {}

    public var status: LoginItemStatus { .unavailable("Not built yet") }

    public func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        throw LoginItemError(message: "Not built yet")
    }

    public func openSystemSettings() {}
}
