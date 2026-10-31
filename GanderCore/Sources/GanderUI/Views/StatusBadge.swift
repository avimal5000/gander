import GanderModels
import SwiftUI

/// A colored dot plus the status line.
struct StatusBadge: View {
    let model: AppModel
    /// The popover keeps one line, so it never changes height when the status or camera name changes.
    var lineLimit = 2

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(model.statusLine)
                .font(.callout)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(model.statusLine)")
    }

    private var color: Color {
        switch model.trackingStatus.tone {
        case .active: GanderPalette.forest
        case .attention: GanderPalette.amber
        case .problem: GanderPalette.brick
        case .idle: Color.secondary
        }
    }
}
