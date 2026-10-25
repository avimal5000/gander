import SwayModels
import SwiftUI

/// Live numbers: Vision yaw/pitch/roll, the landmark proxies, face confidence, and the face indicator.
struct PoseReadoutView: View {
    let model: AppModel

    private var pose: HeadPose? { model.latestSample?.pose }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            sectionTitle("Vision")
            row("Yaw", Formatting.degrees(pose?.yaw))
            row("Pitch", Formatting.degrees(pose?.pitch))
            row("Roll", Formatting.degrees(pose?.roll))
            sectionTitle("Landmark proxy")
            row("Yaw", Formatting.degrees(pose?.landmarkYaw))
            row("Pitch", Formatting.degrees(pose?.landmarkPitch))
            sectionTitle("Detection")
            row("Confidence", pose.map { Formatting.wholePercent($0.faceConfidence) } ?? Formatting.missing)
            GridRow {
                Text("Face").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: pose == nil ? "circle" : "circle.fill")
                        .foregroundStyle(pose == nil ? Color.secondary : SwayPalette.forest)
                        .accessibilityHidden(true)
                    Text(pose == nil ? "Not detected" : "Detected")
                }
            }
        }
        .font(.body)
    }

    private func sectionTitle(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .gridCellColumns(2)
                .padding(.top, 4)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
