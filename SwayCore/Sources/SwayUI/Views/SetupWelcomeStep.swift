import SwiftUI

/// The welcome step (SPEC F26, D40): on first setup, the mark, what Gander does, and the privacy promise, before any
/// permission is asked for.
struct SetupWelcomeStep: View {
    /// Side of the mark's tile.
    static let tileSize: CGFloat = 64
    /// Widest the text goes, so the lines stay a comfortable length in the wide window.
    static let textWidth: CGFloat = 400

    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            tile
            Text(SetupPresentation.welcomeTitle)
                .font(.title.weight(.semibold))
            Text(SetupPresentation.welcomeLine)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.textWidth)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(SwayPalette.accent(for: colorScheme))
                    .accessibilityHidden(true)
                Text(SetupPresentation.welcomePrivacy)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: Self.textWidth)
            .accessibilityElement(children: .combine)
            Button(SetupPresentation.welcomeButton) { model.getStartedFromSetup() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// The green arc on an ivory (light) or charcoal (dark) rounded square, like the app icon.
    private var tile: some View {
        SwayMark(
            arc: SwayPalette.green, start: SwayPalette.sage, end: SwayPalette.green, framing: .unitSquare
        )
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(
            colorScheme == .dark ? SwayPalette.charcoal : SwayPalette.ivory,
            in: RoundedRectangle(cornerRadius: Self.tileSize * 0.225, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.tileSize * 0.225, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
