import SwiftUI

/// The Swing mark (SPEC D36): an arc swinging from a small point to a larger one. Drawn from ``SwayMarkGeometry``, so
/// it matches the menu bar icon and the app icon at any size. Decorative: hidden from accessibility.
struct SwayMark: View {
    /// How the mark sits in its frame.
    enum Framing {
        /// The mark fills the frame (the popover header).
        case fitted
        /// The whole 100 x 100 unit square fills the frame, with the padding the app icon has (the welcome tile).
        case unitSquare
    }

    var arc: Color
    var start: Color
    var end: Color
    var framing: Framing = .fitted

    /// A mark in one color.
    init(color: Color, framing: Framing = .fitted) {
        self.init(arc: color, start: color, end: color, framing: framing)
    }

    init(arc: Color, start: Color, end: Color, framing: Framing = .fitted) {
        self.arc = arc
        self.start = start
        self.end = end
        self.framing = framing
    }

    var body: some View {
        Canvas { context, size in
            let area = CGRect(origin: .zero, size: size)
            let placement =
                switch framing {
                case .fitted: SwayMarkGeometry.placement(fitting: area)
                case .unitSquare: SwayMarkGeometry.placement(unitSquareIn: area)
                }

            var path = Path()
            path.move(to: placement.point(SwayMarkGeometry.start))
            path.addQuadCurve(
                to: placement.point(SwayMarkGeometry.end), control: placement.point(SwayMarkGeometry.control))
            context.stroke(
                path, with: .color(arc),
                style: StrokeStyle(lineWidth: placement.length(SwayMarkGeometry.arcWidth), lineCap: .round))
            context.fill(
                disc(
                    at: placement.point(SwayMarkGeometry.start), radius: placement.length(SwayMarkGeometry.startRadius)),
                with: .color(start))
            context.fill(
                disc(at: placement.point(SwayMarkGeometry.end), radius: placement.length(SwayMarkGeometry.endRadius)),
                with: .color(end))
        }
        .accessibilityHidden(true)
    }

    private func disc(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

#if DEBUG
#Preview("Swing mark") {
    HStack(spacing: 20) {
        SwayMark(color: SwayPalette.green).frame(width: 16, height: 16)
        SwayMark(color: SwayPalette.green).frame(width: 64, height: 64)
        SwayMark(arc: SwayPalette.ivory, start: SwayPalette.sage, end: SwayPalette.ivory, framing: .unitSquare)
            .frame(width: 128, height: 128)
            .background(SwayPalette.forest, in: RoundedRectangle(cornerRadius: 28))
    }
    .padding()
}
#endif
