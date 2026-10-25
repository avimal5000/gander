import ServiceManagement

/// The real `SMAppService.mainApp`, the only place in this module that calls it.
struct MainAppLoginService: LoginItemSystemService {
    var state: LoginItemSystemState {
        LoginItemSystemState(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
