import SwayModels
import SwiftUI

/// A colored dot plus the camera status line.
struct StatusBadge: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(model.statusLine)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera status: \(model.statusLine)")
    }

    private var color: Color {
        switch model.status {
        case .running: SwayPalette.forest
        case .starting, .suspended: SwayPalette.amber
        case .interrupted, .failed: SwayPalette.brick
        case .stopped: Color.secondary
        }
    }
}
