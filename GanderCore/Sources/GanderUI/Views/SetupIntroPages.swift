import SwiftUI

/// A page title in the intro's voice.
private struct IntroTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Page 1: what Gander does, with the animated Fig. 1.
struct SetupIntroWelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IntroTitle(text: SetupPresentation.welcomeTitle)
            Text(SetupPresentation.welcomeHeadline)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(.secondary)
            IntroPlate(label: SetupPresentation.figureLabel, caption: SetupPresentation.welcomeCaption) {
                SetupIntroScene().frame(height: 175)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Page 2: Look. Settle. Type. Three pictograms drawn with shapes.
struct SetupIntroStepsPage: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            IntroTitle(text: SetupPresentation.stepsTitle)
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(SetupPresentation.steps.enumerated()), id: \.offset) { index, text in
                    VStack(alignment: .leading, spacing: 8) {
                        Canvas { context, size in
                            drawing(for: index).draw(context, size: size)
                        }
                        .frame(height: 78)
                        .padding(8)
                        .background(IntroStyle.plate(colorScheme), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(GanderPalette.accent(for: colorScheme).opacity(0.7), lineWidth: 1)
                        )
                        .accessibilityHidden(true)
                        Text("\(index + 1)")
                            .font(.system(.callout, design: .serif).italic())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(text)")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func drawing(for index: Int) -> IntroDrawing {
        var drawing = IntroDrawing(scheme: colorScheme)
        switch index {
        case 0:
            drawing.turn = 0.5
            drawing.showsTurnMarks = true
        case 1:
            drawing.turn = 1
            drawing.showsTarget = true
        default:
            drawing.turn = 1
            drawing.ring = 1
        }
        return drawing
    }
}

/// Page 3: the privacy promise, with the goose in a padlock.
struct SetupIntroPrivacyPage: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            IntroTitle(text: SetupPresentation.privacyTitle)
            HStack(alignment: .center, spacing: 28) {
                padlock
                    .frame(width: 130, height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SetupPresentation.privacyDescription)
                    .accessibilityAddTraits(.isImage)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SetupPresentation.privacyLines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(GanderPalette.accent(for: colorScheme))
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A padlock drawn with shapes, the goose on its body.
    private var padlock: some View {
        let accent = GanderPalette.accent(for: colorScheme)
        return ZStack(alignment: .bottom) {
            Canvas { context, size in
                let w = size.width
                var shackle = Path()
                shackle.move(to: CGPoint(x: w * 0.24, y: size.height * 0.5))
                shackle.addLine(to: CGPoint(x: w * 0.24, y: size.height * 0.3))
                shackle.addArc(
                    center: CGPoint(x: w * 0.5, y: size.height * 0.3), radius: w * 0.26,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                shackle.addLine(to: CGPoint(x: w * 0.76, y: size.height * 0.5))
                context.stroke(shackle, with: .color(accent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            RoundedRectangle(cornerRadius: 14)
                .fill(IntroStyle.plate(colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent, lineWidth: 3))
                .frame(width: 130, height: 90)
                .overlay {
                    GanderMark(color: accent).frame(width: 60, height: 60)
                }
        }
    }
}

/// Page 4: where Gander lives, and what happens next.
struct SetupIntroMenuBarPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IntroTitle(text: SetupPresentation.menuBarTitle)
            strip
            Text(SetupPresentation.menuBarLine)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(SetupPresentation.nextTitle)
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(SetupPresentation.nextSteps.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(.callout, design: .serif).italic())
                            .foregroundStyle(GanderPalette.accent(for: colorScheme))
                            .frame(width: 14, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(text).font(.callout)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1). \(text)")
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A menu bar drawn with shapes: other items as faint pills, the goose with a gentle pulsing ring.
    private var strip: some View {
        let ink = IntroStyle.ink(colorScheme)
        let accent = GanderPalette.accent(for: colorScheme)
        return HStack(spacing: 12) {
            Spacer(minLength: 0)
            ForEach([22.0, 14.0], id: \.self) { width in
                Capsule().fill(ink.opacity(0.22)).frame(width: width, height: 7)
            }
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let phase =
                    reduceMotion
                    ? 0.5 : (timeline.date.timeIntervalSinceReferenceDate / 2.4).truncatingRemainder(dividingBy: 1)
                ZStack {
                    Circle()
                        .strokeBorder(accent.opacity(0.7 * (1 - phase)), lineWidth: 1.5)
                        .frame(width: 22 + 16 * phase, height: 22 + 16 * phase)
                    GanderMark(color: accent).frame(width: 18, height: 18)
                }
                .frame(width: 40, height: 28)
            }
            Capsule().fill(ink.opacity(0.22)).frame(width: 30, height: 7)
            Text("9:41")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(IntroStyle.plate(colorScheme), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupPresentation.menuBarDescription)
        .accessibilityAddTraits(.isImage)
    }
}
