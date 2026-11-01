import AppKit
import SwiftUI

/// The menu bar icon: the Swing mark in the glyph for the one tracking status (SPEC F19, F25).
///
/// Always alive, so it reads only state that changes rarely: the status inputs are assigned on change, and `hasFace`
/// flips only when a face appears or disappears. The images are drawn once (`MenuBarIcon`); this view only picks one.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: model.menuBarGlyph))
            .renderingMode(.template)
            .accessibilityLabel("Gander")
            .accessibilityValue(model.statusLine)
            .onAppear {
                // First run: SwiftUI does not open the Set Up window by itself in a menu bar app, so the icon, which is
                // drawn at launch, opens the walkthrough the first-run rule asked for.
                if model.onboardingPending {
                    openWindow(id: GanderWindowID.setup)
                    NSApp.activate()
                }
            }
    }
}
