import SwiftUI

/// A soft ivory (light) or translucent (dark) rounded container.
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwayPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
    }
}

extension View {
    /// Wraps the view in Gander's card container.
    func swayCard() -> some View {
        modifier(CardStyle())
    }
}
