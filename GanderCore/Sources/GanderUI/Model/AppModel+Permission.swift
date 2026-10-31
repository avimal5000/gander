import Foundation
import GanderModels

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
            case .tracking: await setTrackingEnabled(true)
            case .gateTest: await startGateTest()
            case nil: break
            }
        case .denied:
            permissionPrompt = .denied
            // Tracking stays on, blocked, so access granted later in System Settings resumes it.
            if intent == .tracking { await setTrackingEnabled(true) }
        case .restricted:
            permissionPrompt = .restricted
            if intent == .tracking { await setTrackingEnabled(true) }
        case .notDetermined:
            break
        }
    }

    /// Hides the permission banner without asking for access ("Not now" / "Dismiss").
    func dismissPermissionPrompt() {
        permissionPrompt = nil
        // "Not now" declines the Tracking switch the user just flipped, so it is not restored at the next launch.
        if pendingIntent == .tracking { defaults.set(false, forKey: DefaultsKey.trackingEnabled) }
        pendingIntent = nil
    }

    /// Opens System Settings > Privacy & Security > Camera.
    func openCameraPrivacySettings() {
        environment.system.openCameraPrivacySettings()
    }
}
