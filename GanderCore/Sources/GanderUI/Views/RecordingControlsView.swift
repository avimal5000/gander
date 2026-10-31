#if DEBUG
import SwiftUI

/// Free trace recording (SPEC F6). Compiled into DEBUG builds only; release builds hide the control and never
/// write traces.
struct RecordingControlsView: View {
    let model: AppModel

    var body: some View {
        let recorder = model.recorder
        VStack(alignment: .leading, spacing: 8) {
            Text("Trace recording (debug builds)")
                .font(.headline)
            HStack {
                if recorder.isRecording {
                    Button("Stop and save") { model.stopRecording() }
                        .buttonStyle(.borderedProminent)
                    Label(
                        "Recording \u{00B7} \(recorder.sampleCount) samples",
                        systemImage: "record.circle"
                    )
                    .foregroundStyle(GanderPalette.brick)
                    .monospacedDigit()
                } else {
                    Button("Record") { model.startRecording() }
                        .disabled(!model.isCameraActive)
                    if !model.isCameraActive {
                        Text("Turn the camera on to record.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            result(recorder.lastResult)
        }
        .ganderCard()
    }

    @ViewBuilder
    private func result(_ result: RecordingResult?) -> some View {
        switch result {
        case .saved(let url):
            HStack {
                Text("Saved \(url.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Reveal in Finder") { model.revealInFinder(url) }
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(GanderPalette.brick)
        case nil:
            EmptyView()
        }
    }
}
#endif
