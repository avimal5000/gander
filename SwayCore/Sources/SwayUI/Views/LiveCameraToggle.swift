import SwiftUI

/// The live camera switch shared by the menu and the debug window.
struct LiveCameraToggle: View {
    let model: AppModel

    var body: some View {
        Toggle(isOn: binding) {
            Text("Live camera")
        }
        .toggleStyle(.switch)
        .disabled(model.gateRunState != .idle)
        .help(model.gateRunState == .idle ? "Turn the camera on to see live head pose." : "A gate test is running.")
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { model.liveEnabled },
            set: { newValue in Task { await model.setLiveEnabled(newValue) } }
        )
    }
}
