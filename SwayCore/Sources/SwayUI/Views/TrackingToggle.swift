import SwiftUI

/// The Tracking switch shared by the menu and the debug window. Off is Paused, with the camera off (SPEC D26).
struct TrackingToggle: View {
    let model: AppModel

    var body: some View {
        Toggle(isOn: binding) {
            Text("Tracking")
        }
        .toggleStyle(.switch)
        .disabled(model.gateRunState != .idle)
        .help(
            model.gateRunState == .idle
                ? "Switch focus to the display you look at. Off pauses Sway and turns the camera off."
                : "A calibration is running.")
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { model.trackingEnabled },
            set: { newValue in Task { await model.setTrackingEnabled(newValue) } }
        )
    }
}
