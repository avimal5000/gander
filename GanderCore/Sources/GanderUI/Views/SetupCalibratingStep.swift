import GanderModels
import SwiftUI

/// Step 4: the guided calibration. The full-screen prompts are on the displays; this window mirrors them.
struct SetupCalibratingStep: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let progress = model.gateProgress {
                running(progress)
            } else {
                ProgressView("Starting camera\u{2026}")
            }
            Button("Cancel") { model.cancelCalibration() }
                .keyboardShortcut(.cancelAction)
            Text("Press Esc at any time to cancel.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func running(_ progress: GateProgress) -> some View {
        VStack(spacing: 12) {
            Text("Look at the dot on \(model.displayName(for: progress.display.id))")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(progress.phase == .settle ? "Get ready\u{2026}" : "Hold still")
                .foregroundStyle(.secondary)
            ProgressView(value: progress.fraction)
                .frame(width: 320)
            Text("Step \(progress.stepNumber) of \(progress.stepCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
