import GanderModels
import SwiftUI

/// Step 1: why Gander wants the camera (SPEC F2), then the system prompt; or how to turn access back on.
struct SetupCameraAccessStep: View {
    let model: AppModel

    var body: some View {
        let prompt = Self.prompt(for: model.authorization)
        VStack(alignment: .leading, spacing: 12) {
            Label(CameraPermissionView.title(for: prompt), systemImage: CameraPermissionView.icon(for: prompt))
                .font(.headline)
            Text(Self.message(for: prompt))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch prompt {
            case .explanation:
                Button("Continue") { Task { await model.requestCameraAccessFromSetup() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .denied, .restricted:
                Button("Open System Settings") { model.openCameraPrivacySettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .ganderCard()
        .accessibilityElement(children: .contain)
    }

    /// The explanation until the user decides; then how to change the decision.
    static func prompt(for authorization: CameraAuthorization) -> CameraPermissionPrompt {
        switch authorization {
        case .notDetermined, .authorized: .explanation
        case .denied: .denied
        case .restricted: .restricted
        }
    }

    /// As the camera permission banner says it, except that this window carries on by itself once access is granted.
    static func message(for prompt: CameraPermissionPrompt) -> String {
        switch prompt {
        case .denied:
            "Open System Settings, go to Privacy & Security > Camera, and switch Gander on. "
                + "This window carries on by itself."
        case .explanation, .restricted:
            CameraPermissionView.message(for: prompt)
        }
    }
}
