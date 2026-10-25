import SwiftUI

/// The menu bar icon: an SF Symbol that follows camera and face state.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .accessibilityLabel("Sway")
            .accessibilityValue(model.statusLine)
    }
}
