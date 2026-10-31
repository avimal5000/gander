import SwiftUI

/// The menu bar icon: the Swing mark in the glyph for the one tracking status (SPEC F19, F25).
///
/// Always alive, so it reads only state that changes rarely: the status inputs are assigned on change, and `hasFace`
/// flips only when a face appears or disappears. The images are drawn once (`MenuBarIcon`); this view only picks one.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: model.menuBarGlyph))
            .renderingMode(.template)
            .accessibilityLabel("Gander")
            .accessibilityValue(model.statusLine)
    }
}
