import SwiftUI

/// Step 2: Accessibility access (SPEC F12, F20). The window moves on by itself once it is granted; skipping is allowed.
struct SetupAccessibilityStep: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Allow Gander to move focus", systemImage: "hand.raised")
                .font(.headline)
            Text(FocusTestPresentation.accessibilityExplanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(SetupPresentation.skipConsequence)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Grant Access\u{2026}") { model.grantAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Skip for now") { model.skipSetupAccessibility() }
            }
        }
        .ganderCard()
        .accessibilityElement(children: .contain)
    }
}
