import SwiftUI

/// The colors of the intro, after the Gander landing page: ivory paper in light, charcoal in dark.
enum IntroStyle {
    static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? GanderPalette.charcoal : GanderPalette.ivory
    }

    static func plate(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.6)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? GanderPalette.ivory : GanderPalette.charcoal
    }
}

/// Two monitors, a person seen from behind, a focus ring, and the pointer: the one drawing behind Fig. 1 and the
/// small pictograms. Everything is drawn with shapes in the size it is given.
struct IntroDrawing {
    var scheme: ColorScheme
    /// Head turn, 0 to 1.
    var turn = 0.0
    /// Focus ring position, 0 left monitor to 1 right monitor.
    var ring = 0.0
    var showsRing = true
    /// A dashed ring on the right monitor: where the gaze settles.
    var showsTarget = false
    /// Chevrons beside the head that show it turning.
    var showsTurnMarks = false
    var typed = ""
    var typedOpacity = 1.0
    var showsFigure = true

    init(scheme: ColorScheme, state: IntroSceneState) {
        self.scheme = scheme
        turn = state.turn
        ring = state.ring
        typed = String(IntroSceneState.typedText.prefix(state.typedCount))
        typedOpacity = state.typedOpacity
    }

    init(scheme: ColorScheme) {
        self.scheme = scheme
    }

    func draw(_ context: GraphicsContext, size: CGSize) {
        var context = context
        context.clip(to: Path(CGRect(origin: .zero, size: size)))
        let ink = IntroStyle.ink(scheme)
        let soft = ink.opacity(0.3)
        let accent = GanderPalette.accent(for: scheme)
        let w = size.width
        let h = size.height
        let line = max(1.2, h * 0.009)

        let monitors = [
            CGRect(x: w * 0.06, y: h * 0.05, width: w * 0.39, height: h * 0.52),
            CGRect(x: w * 0.55, y: h * 0.05, width: w * 0.39, height: h * 0.52),
        ]
        for rect in monitors {
            context.stroke(Path(roundedRect: rect, cornerRadius: h * 0.03), with: .color(ink), lineWidth: line)
            var stand = Path()
            stand.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            stand.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + h * 0.06))
            stand.move(to: CGPoint(x: rect.midX - w * 0.05, y: rect.maxY + h * 0.06))
            stand.addLine(to: CGPoint(x: rect.midX + w * 0.05, y: rect.maxY + h * 0.06))
            context.stroke(stand, with: .color(ink), lineWidth: line)
        }

        // Placeholder text on the left monitor.
        for (index, fraction) in [0.7, 0.55, 0.62].enumerated() {
            var rule = Path()
            let y = monitors[0].minY + h * (0.1 + 0.075 * Double(index))
            rule.move(to: CGPoint(x: monitors[0].minX + w * 0.04, y: y))
            rule.addLine(to: CGPoint(x: monitors[0].minX + w * 0.04 + monitors[0].width * fraction, y: y))
            context.stroke(rule, with: .color(soft), style: StrokeStyle(lineWidth: line, lineCap: .round))
        }

        // The typed words, in the right monitor.
        if !typed.isEmpty {
            let text = Text(typed).font(.system(size: max(9, h * 0.075), weight: .medium, design: .monospaced))
            var typedContext = context
            typedContext.opacity = typedOpacity
            typedContext.draw(
                typedContext.resolve(text.foregroundColor(ink)),
                at: CGPoint(x: monitors[1].minX + w * 0.04, y: monitors[1].minY + h * 0.14), anchor: .leading)
        }

        if showsTarget {
            context.stroke(
                Path(roundedRect: monitors[1].insetBy(dx: -h * 0.03, dy: -h * 0.03), cornerRadius: h * 0.05),
                with: .color(accent.opacity(0.7)),
                style: StrokeStyle(lineWidth: line * 1.4, dash: [h * 0.03, h * 0.03]))
        }
        if showsRing {
            let x = monitors[0].minX + (monitors[1].minX - monitors[0].minX) * ring
            let rect = CGRect(x: x, y: monitors[0].minY, width: monitors[0].width, height: monitors[0].height)
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -h * 0.03, dy: -h * 0.03), cornerRadius: h * 0.05),
                with: .color(accent), lineWidth: line * 2.2)
        }

        // The pointer stays on the left monitor.
        let scale = h / 150
        let origin = CGPoint(x: monitors[0].minX + monitors[0].width * 0.5, y: monitors[0].minY + h * 0.3)
        var arrow = Path()
        for (index, point) in [(0, 0), (0, 15), (4, 11.5), (7, 18), (10, 16.5), (7, 10.5), (12, 10.5)].enumerated() {
            let p = CGPoint(x: origin.x + Double(point.0) * scale, y: origin.y + Double(point.1) * scale)
            if index == 0 { arrow.move(to: p) } else { arrow.addLine(to: p) }
        }
        arrow.closeSubpath()
        context.fill(arrow, with: .color(ink))
        context.stroke(arrow, with: .color(IntroStyle.ground(scheme)), lineWidth: line * 0.8)

        guard showsFigure else { return }
        let radius = h * 0.075
        let center = CGPoint(x: w * 0.5 + turn * w * 0.03, y: h * 0.76)
        let shoulders = CGRect(x: w * 0.5 - w * 0.15 + turn * w * 0.01, y: h * 0.86, width: w * 0.3, height: h * 0.4)
        context.stroke(Path(ellipseIn: shoulders), with: .color(ink), lineWidth: line)
        let head = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: head), with: .color(IntroStyle.ground(scheme)))
        context.stroke(Path(ellipseIn: head), with: .color(ink), lineWidth: line)
        if turn > 0.05 {
            // An ear shows as the head turns.
            let ear = CGRect(
                x: center.x + radius * 0.85, y: center.y - radius * 0.2, width: radius * 0.35, height: radius * 0.5)
            context.stroke(Path(ellipseIn: ear), with: .color(ink.opacity(turn)), lineWidth: line)
        }
        if showsTurnMarks {
            var marks = Path()
            for step in 0..<2 {
                let x = center.x + radius * 1.9 + Double(step) * radius * 0.7
                marks.move(to: CGPoint(x: x, y: center.y - radius * 0.4))
                marks.addLine(to: CGPoint(x: x + radius * 0.35, y: center.y))
                marks.addLine(to: CGPoint(x: x, y: center.y + radius * 0.4))
            }
            context.stroke(
                marks, with: .color(accent),
                style: StrokeStyle(lineWidth: line * 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Fig. 1: the animated scene. A ten second loop; one still frame with Reduce Motion.
struct SetupIntroScene: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? IntroSceneState.stillTime : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                IntroDrawing(scheme: colorScheme, state: IntroSceneState(at: time)).draw(context, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupPresentation.welcomeSceneDescription)
        .accessibilityAddTraits(.isImage)
    }
}

/// A figure in a plate: a double-ruled frame and an italic serif caption under a "Fig." label, as on the landing page.
struct IntroPlate<Content: View>: View {
    let label: String
    let caption: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .padding(14)
                .background(IntroStyle.plate(colorScheme), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GanderPalette.accent(for: colorScheme), lineWidth: 1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(IntroStyle.ink(colorScheme).opacity(0.18), lineWidth: 1)
                        .padding(5)
                )
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GanderPalette.accent(for: colorScheme))
                    .accessibilityHidden(true)
                Text(caption)
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(IntroStyle.ink(colorScheme).opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
