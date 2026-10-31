import GanderModels
import SwiftUI

/// The Head-Pose Gate Test window (SPEC F7-F9): setup, a running state, and the report.
struct GateTestView: View {
    @Bindable var model: AppModel

    var body: some View {
        // One stable container: lifecycle modifiers on a bare `if`/`else` would fire again on every branch switch.
        VStack(spacing: 0) {
            content
        }
        .frame(minWidth: 700, minHeight: 600)
        .tint(model.accentChoice.tint)
        .onAppear { model.refreshEnvironment() }
        .launchGuarded(id: GanderWindowID.gateTest, model: model)
        // Closing the window must never leave overlays on screen with no way to cancel them.
        .onDisappear { model.cancelGateTest(reason: nil) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isGateTestRunning {
            GateRunningView(model: model)
        } else if model.isShowingReport, model.analysis != nil {
            GateReportView(model: model)
        } else {
            GateSetupView(model: model)
        }
    }
}

#if DEBUG
#Preview("Gate setup") {
    GateTestView(model: PreviewSupport.model())
}

#Preview("Gate report") {
    GateTestView(model: PreviewSupport.model(withAnalysis: true, showReport: true))
}
#endif
