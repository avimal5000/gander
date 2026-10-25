import SwayModels
import SwiftUI

/// The Set Up Sway window (SPEC F20): camera access, Accessibility, a camera check, the guided calibration, and its
/// result, one step at a time. `SetupFlow` decides the step; this view only draws it.
struct SetupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let flow = model.setupFlow {
                header(for: flow.step)
                content(for: flow.step)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420, alignment: .topLeading)
        .onAppear { model.setupWindowDidAppear() }
        .onDisappear { model.setupWindowDidDisappear() }
        .launchGuarded(id: SwayWindowID.setup, model: model)
    }

    private func header(for step: SetupFlow.Step) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(step.rawValue) of \(SetupFlow.stepCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.title(for: step))
                .font(.title2.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(for step: SetupFlow.Step) -> some View {
        switch step {
        case .cameraAccess: SetupCameraAccessStep(model: model)
        case .accessibility: SetupAccessibilityStep(model: model)
        case .cameraCheck: SetupCameraCheckStep(model: model)
        case .calibrating: SetupCalibratingStep(model: model)
        case .result: SetupResultStep(model: model)
        }
    }

    static func title(for step: SetupFlow.Step) -> String {
        switch step {
        case .cameraAccess: "Camera access"
        case .accessibility: "Accessibility access"
        case .cameraCheck: "Check your camera"
        case .calibrating: "Look at each display"
        case .result: "Calibration result"
        }
    }
}

#if DEBUG
#Preview("Setup, camera check") {
    SetupView(model: PreviewSupport.setupModel(step: .cameraCheck))
}

#Preview("Setup, result") {
    SetupView(model: PreviewSupport.setupModel(step: .result))
}
#endif
