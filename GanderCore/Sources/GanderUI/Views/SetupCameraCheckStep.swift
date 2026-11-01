import GanderModels
import SwiftUI

/// Step 3: the camera runs and Gander says whether it sees a face and whether to move (SPEC F20).
struct SetupCameraCheckStep: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(SetupPresentation.cameraAdvice)
                    .fixedSize(horizontal: false, vertical: true)
                CameraPickerView(model: model)
                FramingHintView(model: model)
            }
            .ganderCard()
            if let message = model.setupMessage { MessageView(message: message) }
            if model.canStartCalibration {
                HStack(spacing: 12) {
                    Button("Start calibration") { Task { await model.startCalibration() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Text(duration)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                MessageView(message: .info(SetupPresentation.calibrateLater))
                Button("Done") { dismissWindow(id: GanderWindowID.setup) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var duration: String {
        let seconds = GateTestConfiguration.calibration.estimatedDuration(displayCount: model.layout.displays.count)
        return "About \(Formatting.seconds(seconds))."
    }
}

/// The live hint under the picker. Its own view, so only it follows the camera status and the hint (which changes at
/// most five times a second).
private struct FramingHintView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.status {
            case .running:
                Image(
                    systemName: model.framingAdvice == .good
                        ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark"
                )
                .foregroundStyle(model.framingAdvice == .good ? GanderPalette.forest : GanderPalette.amber)
                .accessibilityHidden(true)
                Text(model.framingAdvice.text)
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GanderPalette.brick)
                    .accessibilityHidden(true)
                Text("The camera could not start: \(error.userMessage).")
                Button("Try again") { model.retrySetupCamera() }
            case .interrupted, .suspended:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GanderPalette.amber)
                    .accessibilityHidden(true)
                Text(model.status.summary)
            case .starting, .stopped:
                ProgressView()
                    .controlSize(.small)
                Text("Starting camera\u{2026}")
            }
        }
        .font(.callout.weight(.medium))
        .frame(minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
