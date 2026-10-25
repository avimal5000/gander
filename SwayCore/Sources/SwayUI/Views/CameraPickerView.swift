import SwayModels
import SwiftUI

/// Chooses which camera to use: "Default (built-in)" or one of the connected devices.
struct CameraPickerView: View {
    let model: AppModel
    /// Tag for the "default" row (a `nil` selection cannot be a picker tag on its own).
    private static let defaultTag = ""

    var body: some View {
        Picker("Camera", selection: selection) {
            Text("Default (built-in)").tag(Self.defaultTag)
            ForEach(model.devices) { device in
                Text(device.name).tag(device.id)
            }
            if let missing = unavailableSelection {
                Text("Unavailable camera (uses default)").tag(missing)
            }
        }
        .disabled(model.gateRunState != .idle)
    }

    /// The saved camera ID when that device is not connected right now.
    private var unavailableSelection: String? {
        guard let id = model.selectedCameraID, !model.devices.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private var selection: Binding<String> {
        Binding(
            get: { model.selectedCameraID ?? Self.defaultTag },
            set: { newValue in
                let id = newValue == Self.defaultTag ? nil : newValue
                Task { await model.selectCamera(id) }
            }
        )
    }
}
