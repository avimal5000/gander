import AppKit
import GanderModels
import SwiftUI

/// The Set Up Gander window (SPEC F20, F26): a welcome on first setup, then camera access, Accessibility, a camera check,
/// the guided calibration, and its result, one step at a time. `SetupFlow` decides the step; this view only draws it.
struct SetupView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // One step at a time, cross-fading over the same area when the step changes (F29).
        ZStack(alignment: .topLeading) {
            if let flow = model.setupFlow {
                stepView(for: flow.step)
                    .id(flow.step)
                    .transition(.opacity)
            }
        }
        .animation(Self.stepAnimation(reduceMotion: reduceMotion), value: model.setupFlow?.step)
        .padding(24)
        .frame(width: 560, height: 480, alignment: .topLeading)
        .background {
            if model.setupFlow?.step == .welcome { IntroStyle.ground(colorScheme).ignoresSafeArea() }
        }
        .tint(model.accentChoice.tint)
        .onAppear {
            // The first-run walkthrough opens by itself: bring it in front of the other apps.
            if model.setupWindowDidAppear() { NSApp.activate() }
        }
        .onDisappear { model.setupWindowDidDisappear() }
        .launchGuarded(id: GanderWindowID.setup, model: model)
    }

    /// The fade between steps: about 0.2 s, none with Reduce Motion.
    static func stepAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    @ViewBuilder
    private func stepView(for step: SetupFlow.Step) -> some View {
        if step == .welcome {
            SetupWelcomeStep(model: model)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                SetupHeader(step: step)
                content(for: step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func content(for step: SetupFlow.Step) -> some View {
        switch step {
        case .welcome: EmptyView()
        case .cameraAccess: SetupCameraAccessStep(model: model)
        case .accessibility: SetupAccessibilityStep(model: model)
        case .cameraCheck: SetupCameraCheckStep(model: model)
        case .calibrating: SetupCalibratingStep(model: model)
        case .result: SetupResultStep(model: model)
        }
    }

    static func title(for step: SetupFlow.Step) -> String {
        switch step {
        case .welcome: SetupPresentation.welcomeTitle
        case .cameraAccess: "Camera access"
        case .accessibility: "Accessibility access"
        case .cameraCheck: "Check your camera"
        case .calibrating: "Look at each display"
        case .result: "Calibration result"
        }
    }
}

/// The header every numbered Setup step shares: the mark, "Step N of 5", and the step's title.
struct SetupHeader: View {
    /// Size of the mark.
    static let markSize: CGFloat = 24

    let step: SetupFlow.Step

    var body: some View {
        HStack(spacing: 10) {
            GanderMark(color: GanderPalette.green)
                .frame(width: Self.markSize, height: Self.markSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(step.rawValue) of \(SetupFlow.stepCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SetupView.title(for: step))
                    .font(.title2.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
#Preview("Setup, welcome") {
    SetupView(model: PreviewSupport.setupModel(step: .welcome))
}

#Preview("Setup, camera check") {
    SetupView(model: PreviewSupport.setupModel(step: .cameraCheck))
}

#Preview("Setup, result") {
    SetupView(model: PreviewSupport.setupModel(step: .result))
}
#endif
