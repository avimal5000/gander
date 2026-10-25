/// The three system calls behind the login item, so `MainAppLoginItem`'s routing and error wording can be tested
/// with a fake that never touches the user's real login items.
protocol LoginItemSystemService {
    /// The current registration state, read fresh from the system.
    var state: LoginItemSystemState { get }
    /// Registers the app as a login item.
    func register() throws
    /// Removes the app from the login items.
    func unregister() throws
    /// Opens System Settings > General > Login Items.
    func openSystemSettings()
}
