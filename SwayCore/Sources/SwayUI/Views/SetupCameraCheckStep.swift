import SwayModels
import SwiftUI

/// Step 3: the camera runs and Sway says whether it sees a face and whether to move (SPEC F20).
struct SetupCameraCheckStep: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text(SetupPresentation.cameraAdvice)
                    .fixedSize(horizontal: false, vertical: true)
                CameraPickerView(model: model)
                FramingHintView(model: model)
            }
            .swayCard()
            if let message = model.setupMessage { MessageView(message: message) }
            if !model.canStartCalibration {
                MessageView(message: .info(SetupPresentation.needsSecondDisplay))
            }
            HStack(spacing: 12) {
                Button("Start calibration") { Task { await model.startCalibration() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStartCalibration)
                if model.canStartCalibration {
                    Text(duration)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
                .foregroundStyle(model.framingAdvice == .good ? SwayPalette.forest : SwayPalette.amber)
                .accessibilityHidden(true)
                Text(model.framingAdvice.text)
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SwayPalette.brick)
                    .accessibilityHidden(true)
                Text("The camera could not start: \(error.userMessage).")
                Button("Try again") { model.retrySetupCamera() }
            case .interrupted, .suspended:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SwayPalette.amber)
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
