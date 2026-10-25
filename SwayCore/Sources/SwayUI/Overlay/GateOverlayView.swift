import SwayModels
import SwiftUI

/// What the user sees on the display they are asked to look at: a forest-green border, a centered target dot, the
/// prompt, and the settle countdown or hold progress.
struct GateOverlayView: View {
    /// Fade duration for appearing and disappearing.
    static let fadeDuration = 0.3

    let model: GateOverlayModel

    private var progress: GateProgress { model.progress }

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
            // Forest border, with a thin ivory line just inside it so it also reads on dark desktops.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(SwayPalette.forest, lineWidth: 14)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(SwayPalette.ivory.opacity(0.85), lineWidth: 2)
                .padding(14)
            // Two equal halves meet at the exact center of the screen, where the target sits; the prompt hangs
            // below the target.
            VStack(spacing: 0) {
                Color.clear
                Color.clear.overlay(alignment: .top) { prompt.padding(.top, 72) }
            }
            TargetDot()
        }
        .ignoresSafeArea()
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: Self.fadeDuration), value: model.isVisible)
        .onAppear { model.isVisible = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Look at the center of this screen")
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Text("Look at the center of this screen")
                .font(.system(size: 26, weight: .semibold))
            Text("Round \(progress.round) of \(progress.rounds) \u{00B7} \(progress.display.name)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            statusRow
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusRow: some View {
        switch progress.phase {
        case .settle:
            Text("Get ready\u{2026} \(Int(progress.remaining.rounded(.up)))")
                .font(.system(size: 18, weight: .medium).monospacedDigit())
                .foregroundStyle(SwayPalette.forest)
        case .hold:
            VStack(spacing: 6) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(SwayPalette.forest)
                    .frame(width: 260)
                Text("Hold still \u{00B7} \(Int(progress.remaining.rounded(.up))) s")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Concentric rings and a solid dot at the exact center of the screen.
private struct TargetDot: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(SwayPalette.forest.opacity(0.35), lineWidth: 3)
                .frame(width: 84, height: 84)
            Circle()
                .stroke(SwayPalette.forest, lineWidth: 4)
                .frame(width: 52, height: 52)
            Circle()
                .fill(SwayPalette.forest)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(SwayPalette.ivory, lineWidth: 2))
        }
    }
}

#if DEBUG
#Preview("Overlay, hold phase") {
    let progress = GateProgress(
        phase: .hold, stepNumber: 1, stepCount: 4, round: 1, rounds: 2, displayNumber: 1, displayCount: 2,
        display: PreviewSupport.leftDisplay, phaseElapsed: 2, phaseDuration: 5, recordedSamples: 30,
        recordedFaces: 29
    )
    GateOverlayView(model: GateOverlayModel(progress: progress))
        .frame(width: 960, height: 540)
}
#endif
