import Foundation
import SwayModels

// Camera permission flow (SPEC F2): explain first, then trigger the system prompt; if access is denied, show
// instructions with a button that opens System Settings.
extension AppModel {
    /// The user accepted the explanation: show the system prompt, then resume what they were doing.
    func continueAfterPermissionExplanation() async {
        guard permissionPrompt == .explanation else { return }
        permissionPrompt = nil
        let intent = pendingIntent
        pendingIntent = nil

        let result = await camera.requestAuthorization()
        authorization = result
        switch result {
        case .authorized:
            switch intent {
            case .live: await setLiveEnabled(true)
            case .gateTest: await startGateTest()
            case nil: break
            }
        case .denied:
            permissionPrompt = .denied
        case .restricted:
            permissionPrompt = .restricted
        case .notDetermined:
            break
        }
    }

    /// Hides the permission banner without asking for access ("Not now" / "Dismiss").
    func dismissPermissionPrompt() {
        permissionPrompt = nil
        pendingIntent = nil
    }

    /// Opens System Settings > Privacy & Security > Camera.
    func openCameraPrivacySettings() {
        environment.system.openCameraPrivacySettings()
    }
}
