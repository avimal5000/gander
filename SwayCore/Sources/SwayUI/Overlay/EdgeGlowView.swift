import SwiftUI

/// The edge glow (SPEC F27): a 4 pt Sway-green border along the edges of the display, with a soft glow of about 10 pt
/// just inside it that fades out from 40% opacity. Static: the panel fades it, and nothing redraws while it shows.
struct EdgeGlowView: View {
    /// Width of the solid border.
    static let borderWidth: CGFloat = 4
    /// Width of the soft glow inside the border.
    static let glowWidth: CGFloat = 10
    /// Opacity of the glow next to the border.
    static let glowOpacity = 0.4

    /// Opacity of the glow ring `index` (0 touches the border), falling off quadratically to nearly nothing.
    static func ringOpacity(at index: Int) -> Double {
        let position = (Double(index) + 0.5) / Double(glowWidth)
        return glowOpacity * (1 - position) * (1 - position)
    }

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            for index in 0..<Int(Self.glowWidth) {
                let inset = Self.borderWidth + CGFloat(index) + 0.5
                context.stroke(
                    Path(bounds.insetBy(dx: inset, dy: inset)),
                    with: .color(SwayPalette.green.opacity(Self.ringOpacity(at: index))), lineWidth: 1)
            }
            context.stroke(
                Path(bounds.insetBy(dx: Self.borderWidth / 2, dy: Self.borderWidth / 2)),
                with: .color(SwayPalette.green), lineWidth: Self.borderWidth)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Edge glow") {
    EdgeGlowView()
        .frame(width: 640, height: 360)
        .background(Color.gray.opacity(0.3))
}
#endif
