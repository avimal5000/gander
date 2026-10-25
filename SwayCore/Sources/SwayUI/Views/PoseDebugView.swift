import SwayModels
import SwiftUI

/// The Pose Debug window (SPEC F5/F6/F11): live numbers, schematic face box, 10 s plot, the live guess, and the
/// Switch preview.
struct PoseDebugView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                CameraPermissionView(model: model)
                HStack(spacing: 20) {
                    LiveCameraToggle(model: model)
                    CameraPickerView(model: model)
                        .frame(maxWidth: 320)
                }
                HStack(alignment: .top, spacing: 24) {
                    PoseReadoutView(model: model)
                    VStack(alignment: .leading, spacing: 6) {
                        FaceBoxView(faceBounds: model.latestSample?.pose?.faceBounds)
                            .frame(maxWidth: 240)
                        Text("Schematic camera frame. Sway never shows or stores video.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swayCard()
                PosePlotView(model: model)
                LiveGuessView(model: model)
                SwitchPreviewView(model: model)
                #if DEBUG
                RecordingControlsView(model: model)
                #endif
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 640)
        .onAppear { model.refreshEnvironment() }
        .launchGuarded(id: SwayWindowID.poseDebug, model: model)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            StatusBadge(model: model)
            Spacer()
            if let name = model.currentCameraName {
                Label(name, systemImage: "web.camera")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(model.status.isRunning ? Formatting.fps(model.fps) : Formatting.missing)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Measured frame rate")
        }
    }

}

#if DEBUG
#Preview("Pose Debug with live guess") {
    PoseDebugView(model: PreviewSupport.model(live: true, withAnalysis: true, withProfile: true))
}
#endif
