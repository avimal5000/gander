import SwiftUI

/// The Gander mark: a goose, with its wing in the `start` colour and its eye cut out. Drawn from ``GanderMarkGeometry``, so
/// it matches the menu bar icon and the app icon at any size. Decorative: hidden from accessibility.
struct GanderMark: View {
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
                case .fitted: GanderMarkGeometry.placement(fitting: area)
                case .unitSquare: GanderMarkGeometry.placement(unitSquareIn: area)
                }

            var body = Path(GanderMarkGeometry.silhouette(in: placement))
            body.addPath(Path(GanderMarkGeometry.eye(in: placement)))
            context.fill(body, with: .color(arc), style: FillStyle(eoFill: true))
            context.fill(Path(GanderMarkGeometry.wing(in: placement)), with: .color(start))
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Gander mark") {
    HStack(spacing: 20) {
        GanderMark(color: GanderPalette.green).frame(width: 16, height: 16)
        GanderMark(color: GanderPalette.green).frame(width: 64, height: 64)
        GanderMark(arc: GanderPalette.ivory, start: GanderPalette.sage, end: GanderPalette.ivory, framing: .unitSquare)
            .frame(width: 128, height: 128)
            .background(GanderPalette.forest, in: RoundedRectangle(cornerRadius: 28))
    }
    .padding()
}
#endif
