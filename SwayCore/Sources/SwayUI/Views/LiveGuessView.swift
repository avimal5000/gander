import AppKit
import SwayModels
import SwiftUI

/// "Live guess: <display>" once an analysis exists (SPEC F5), with the normalized distances behind it.
struct LiveGuessView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let best = model.analysis?.bestFeatureSet {
                guess(best)
            } else {
                Text("Live guess")
                    .font(.headline)
                Text(
                    "Run the head-pose gate test, or open a saved trace there, to see which display you are looking at."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Open Gate Test\u{2026}") {
                    model.noteWindowRequested(SwayWindowID.gateTest)
                    openWindow(id: SwayWindowID.gateTest)
                    NSApp.activate()
                }
            }
        }
        .swayCard()
    }

    @ViewBuilder
    private func guess(_ best: PoseFeatureSet) -> some View {
        if let classification = model.liveClassification, let name = model.liveGuessName {
            Text("Live guess: \(name)")
                .font(.title3.weight(.semibold))
            Text(distances(classification))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("Live guess")
                .font(.headline)
            Text(model.status.isRunning ? "No face detected" : "Turn the camera on to see a live guess.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Text("Using \((model.liveGuessFeatureSet ?? best).title) from \(sourceDescription)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func distances(_ classification: DisplayClassification) -> String {
        var text = "z \(Formatting.oneDecimal(classification.distance))"
        if let runnerUp = classification.runnerUpDistance {
            text += ", runner-up z \(Formatting.oneDecimal(runnerUp))"
        }
        return text
    }

    private var sourceDescription: String {
        switch model.analysisSource {
        case .gateTest: "the latest gate test"
        case .file(let url): url.lastPathComponent
        case nil: "the latest analysis"
        }
    }
}
