import SwiftUI

/// The menu bar icon: an SF Symbol that follows the one tracking status (SPEC F19).
///
/// Always alive, so it reads only state that changes rarely: the status inputs are assigned on change, and `hasFace`
/// flips only when a face appears or disappears.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.trackingStatus.symbol)
            .accessibilityLabel("Sway")
            .accessibilityValue(model.statusLine)
    }
}
