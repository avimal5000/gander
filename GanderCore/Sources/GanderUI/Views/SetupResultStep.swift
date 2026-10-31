import GanderModels
import SwiftUI

/// Step 5: how well the new calibration separates the displays, with Start tracking and Calibrate again.
struct SetupResultStep: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = model.setupResult {
                Label {
                    Text(result.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: Self.symbol(for: result.quality))
                        .foregroundStyle(Self.color(for: result.quality))
                }
                .font(.headline)
                .ganderCard()
                actions(for: result)
            }
        }
    }

    private func actions(for result: SetupResult) -> some View {
        HStack(spacing: 12) {
            if result.isSaved {
                Button("Start tracking") {
                    Task {
                        await model.startTrackingFromSetup()
                        dismissWindow(id: GanderWindowID.setup)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Calibrate again") { model.calibrateAgain() }
            } else {
                Button("Calibrate again") { model.calibrateAgain() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    static func symbol(for quality: SetupResult.Quality) -> String {
        switch quality {
        case .good: "checkmark.circle.fill"
        case .fair, .poor: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    static func color(for quality: SetupResult.Quality) -> Color {
        switch quality {
        case .good: GanderPalette.forest
        case .fair: GanderPalette.amber
        case .poor, .failed: GanderPalette.brick
        }
    }
}
