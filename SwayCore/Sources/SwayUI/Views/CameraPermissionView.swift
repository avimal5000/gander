import SwiftUI

/// Explains why Sway wants the camera before the system prompt (SPEC F2), or shows how to re-enable access.
struct CameraPermissionView: View {
    let model: AppModel

    var body: some View {
        if let prompt = model.permissionPrompt {
            VStack(alignment: .leading, spacing: 8) {
                Label(title(for: prompt), systemImage: icon(for: prompt))
                    .font(.headline)
                Text(message(for: prompt))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    switch prompt {
                    case .explanation:
                        Button("Continue") { Task { await model.continueAfterPermissionExplanation() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        Button("Not now") { model.dismissPermissionPrompt() }
                    case .denied, .restricted:
                        Button("Open System Settings") { model.openCameraPrivacySettings() }
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss") { model.dismissPermissionPrompt() }
                    }
                }
            }
            .swayCard()
            .accessibilityElement(children: .contain)
        }
    }

    private func title(for prompt: CameraPermissionPrompt) -> String {
        switch prompt {
        case .explanation: "Sway needs your camera"
        case .denied: "Camera access is off"
        case .restricted: "Camera access is restricted"
        }
    }

    private func icon(for prompt: CameraPermissionPrompt) -> String {
        switch prompt {
        case .explanation: "camera"
        case .denied: "camera.badge.ellipsis"
        case .restricted: "lock"
        }
    }

    private func message(for prompt: CameraPermissionPrompt) -> String {
        switch prompt {
        case .explanation:
            "Sway reads your head pose from the camera to work out which display you are looking at. "
                + "Frames are processed in memory and never saved or sent anywhere. macOS will ask for permission next."
        case .denied:
            "Open System Settings, go to Privacy & Security > Camera, and switch Sway on. "
                + "Then turn the camera on again here."
        case .restricted:
            "A device policy or parental control prevents Sway from using the camera on this Mac. "
                + "Open System Settings > Privacy & Security > Camera to see what is allowed."
        }
    }
}
