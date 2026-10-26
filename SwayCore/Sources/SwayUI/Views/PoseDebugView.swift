import SwayModels
import SwiftUI

/// The Pose Debug window (SPEC F5/F6/F11): live numbers, schematic face box, 10 s plot, the live guess, and the
/// Switch preview.
struct PoseDebugView: View {
    @Bindable var model: AppModel
    /// False while the window is closed or minimized. SwiftUI keeps a closed window's views alive, and without this
    /// they would keep redrawing for every camera frame (`WindowVisibility`).
    @State private var showsLiveContent = true

    var body: some View {
        ScrollView {
            if showsLiveContent {
                content
            }
        }
        // Bounds on both sides of each axis: the window's minimum size then comes from this frame alone. With only
        // minimums, AppKit re-measured the whole content (plot included) on every update, once per camera frame.
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity)
        .background(
            WindowVisibilityReader {
                showsLiveContent = $0
                model.setPoseDebugVisible($0)
            }
        )
        .tint(model.accentChoice.tint)
        .onAppear {
            model.refreshEnvironment()
            // Its live numbers and plot need every frame (SPEC D45): the pose source runs at the full rate meanwhile.
            model.setPoseDebugVisible(true)
        }
        .onDisappear { model.setPoseDebugVisible(false) }
        .launchGuarded(id: SwayWindowID.poseDebug, model: model)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            CameraPermissionView(model: model)
            HStack(spacing: 20) {
                TrackingToggle(model: model)
                CameraPickerView(model: model)
                    .frame(maxWidth: 320)
            }
            HStack(alignment: .top, spacing: 24) {
                PoseReadoutView(model: model)
                VStack(alignment: .leading, spacing: 6) {
                    LiveFaceBox(model: model)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            StatusBadge(model: model)
            Spacer()
            if let name = model.currentCameraName {
                Label(name, systemImage: "web.camera")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(model.status.isRunning ? Formatting.fps(model.readout.fps) : Formatting.missing)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Measured frame rate")
        }
    }

}

/// The face box at the frame rate. Its own view, so a new frame redraws the box and not the whole window, whose other
/// per-frame parts (plot, switch preview) read the model themselves too.
private struct LiveFaceBox: View {
    let model: AppModel

    var body: some View {
        FaceBoxView(faceBounds: model.latestSample?.pose?.faceBounds)
    }
}

#if DEBUG
#Preview("Pose Debug with live guess") {
    PoseDebugView(model: PreviewSupport.model(tracking: true, withAnalysis: true, withProfile: true))
}
#endif
