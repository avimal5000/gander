import SwayModels
import SwiftUI

/// Shown in the gate window while the test runs; the real prompt is on the overlays.
struct GateRunningView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            if let progress = model.gateProgress {
                running(progress)
            } else {
                ProgressView("Starting camera\u{2026}")
            }
            Button("Cancel") { model.cancelGateTest(reason: "Gate test cancelled.") }
                .keyboardShortcut(.cancelAction)
            Text("Press Esc at any time to cancel.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }

    private func running(_ progress: GateProgress) -> some View {
        VStack(spacing: 12) {
            Text(
                "Round \(progress.round) of \(progress.rounds) \u{00B7} Display \(progress.displayNumber) of \(progress.displayCount)"
            )
            .font(.headline)
            Text("Look at the center of \(progress.display.name)")
                .font(.title2.weight(.semibold))
            Text(progress.phase == .settle ? "Get ready\u{2026}" : "Hold still")
                .foregroundStyle(.secondary)
            ProgressView(value: progress.fraction)
                .tint(SwayPalette.forest)
                .frame(width: 320)
            if progress.phase == .hold {
                Text("\(progress.recordedSamples) samples \u{00B7} \(progress.recordedFaces) with a face")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Step \(progress.stepNumber) of \(progress.stepCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
