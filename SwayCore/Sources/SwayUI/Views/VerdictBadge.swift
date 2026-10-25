import SwayModels
import SwiftUI

/// The GO / MARGINAL / NO-GO / insufficient-data pill.
struct VerdictBadge: View {
    let verdict: GateVerdict
    var large = false

    var body: some View {
        Text(verdict.title)
            .font(large ? .title2.weight(.bold) : .caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 14 : 8)
            .padding(.vertical, large ? 6 : 3)
            .background(verdict.color, in: Capsule())
            .accessibilityLabel("Verdict: \(verdict.title)")
    }
}

extension GateVerdict {
    /// Badge color; every choice keeps white text legible in both appearances.
    var color: Color {
        switch self {
        case .go: SwayPalette.forest
        case .marginal: SwayPalette.amber
        case .noGo: SwayPalette.brick
        case .insufficientData: Color(white: 0.45)
        }
    }
}
