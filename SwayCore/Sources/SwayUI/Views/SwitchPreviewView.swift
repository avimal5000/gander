import AppKit
import SwayModels
import SwiftUI

/// The "Switch preview" section of the Pose Debug window (SPEC F11): what the decider sees and would do, with a
/// simulated focus. Nothing here moves real focus.
struct SwitchPreviewView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Switch preview")
                .font(.headline)
            if model.calibrationProfile == nil {
                missingProfile
            } else {
                preview
            }
        }
        .swayCard()
    }

    private var missingProfile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SwitchPreviewPresentation.noProfile)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Gate Test\u{2026}") {
                model.noteWindowRequested(SwayWindowID.gateTest)
                openWindow(id: SwayWindowID.gateTest)
                NSApp.activate()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let names = DisplayLabeler.labels(for: model.layout)
        let name: (DisplayID) -> String = { names[$0] ?? model.displayName(for: $0) }
        if model.isCalibrationStale {
            Label(SwitchPreviewPresentation.stale, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(SwayPalette.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !model.liveEnabled {
            Text(SwitchPreviewPresentation.cameraOff)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        classificationRow(name)
        phaseRow(name)
        Text(SwitchPreviewPresentation.simulatedFocusText(model.simulatedFocus, name: name))
            .font(.callout.weight(.medium))
        Toggle("Simulate Focus Lock", isOn: $model.simulateFocusLock)
            .toggleStyle(.switch)
        log
    }

    private func classificationRow(_ name: (DisplayID) -> String) -> some View {
        let classification = model.previewDecision?.classification
        return VStack(alignment: .leading, spacing: 4) {
            Text(SwitchPreviewPresentation.classificationText(classification, name: name))
                .font(.title3.weight(.semibold))
            if let margin = SwitchPreviewPresentation.margin(classification) {
                HStack(spacing: 8) {
                    Text("Margin").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: margin, total: 1)
                        .tint(SwayPalette.forest)
                        .accessibilityLabel("Margin over the next nearest display")
                        .accessibilityValue(Formatting.twoDecimals(margin))
                    Text(Formatting.twoDecimals(margin)).font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func phaseRow(_ name: (DisplayID) -> String) -> some View {
        let phase = model.previewDecision?.phase
        return VStack(alignment: .leading, spacing: 4) {
            Text(SwitchPreviewPresentation.phaseText(phase, name: name))
                .font(.callout)
            if let progress = SwitchPreviewPresentation.dwellProgress(phase) {
                ProgressView(value: progress, total: 1)
                    .tint(SwayPalette.forest)
                    .accessibilityLabel("Dwell progress")
                    .accessibilityValue(Formatting.wholePercent(progress))
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Would-be switches")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if model.switchLog.isEmpty {
                Text(SwitchPreviewPresentation.noSwitches)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.switchLog) { entry in
                HStack(spacing: 10) {
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(SwitchPreviewPresentation.logText(entry))
                        .font(.callout)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Switch preview, calibrated") {
    SwitchPreviewView(model: PreviewSupport.model(live: true, withAnalysis: true, withProfile: true))
        .padding()
        .frame(width: 520)
}

#Preview("Switch preview, not calibrated") {
    SwitchPreviewView(model: PreviewSupport.model())
        .padding()
        .frame(width: 520)
}
#endif
