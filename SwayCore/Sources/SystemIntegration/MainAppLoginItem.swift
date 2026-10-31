import SwayModels

/// Opens Gander at login through `SMAppService.mainApp` (CONTRACT 6.8). macOS may ask the user to approve it in
/// System Settings, and it works reliably only for a copy of the app in `/Applications`.
@MainActor
public final class MainAppLoginItem: LoginItemControlling {
    private let service: any LoginItemSystemService
    private let logger = SwayLog.logger(category: "system")

    public init() {
        service = MainAppLoginService()
    }

    /// Tests inject a fake service so no real login item is ever registered.
    init(service: any LoginItemSystemService) {
        self.service = service
    }

    /// The current state, read fresh from the system.
    public var status: LoginItemStatus {
        LoginItemMapping.status(for: service.state)
    }

    /// Registers (`true`) or unregisters (`false`) the app as a login item. A system failure becomes a
    /// `LoginItemError` whose message includes the system's description. Asking for the state the item is already in
    /// does nothing: the system would only report an error.
    public func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        if service.state == (enabled ? .enabled : .notRegistered) { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let message = LoginItemMapping.failureMessage(
                enabling: enabled, systemDescription: error.localizedDescription)
            logger.error("Login item change failed: \(message, privacy: .public)")
            throw LoginItemError(message: message)
        }
        logger.info("Login item \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    /// Opens System Settings > General > Login Items.
    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
