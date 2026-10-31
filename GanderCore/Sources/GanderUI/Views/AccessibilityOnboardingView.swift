import SwiftUI

/// Accessibility status and the "Grant Access…" button at the top of the Focus Test window (SPEC F12).
struct AccessibilityOnboardingView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isAccessibilityTrusted ? GanderPalette.forest : GanderPalette.amber)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(
                    model.isAccessibilityTrusted
                        ? FocusTestPresentation.accessibilityGranted : FocusTestPresentation.accessibilityNotGranted
                )
                .font(.headline)
            }
            if !model.isAccessibilityTrusted {
                Text(FocusTestPresentation.accessibilityExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Grant Access\u{2026}") { model.grantAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .ganderCard()
        .accessibilityElement(children: .contain)
    }
}
