import AppKit
import SwayModels
import SwiftUI

/// The Sway Settings window (SPEC F21, D33): login item, switching, the Focus Lock shortcut, the camera, and the
/// saved calibrations. A regular window, because SwiftUI's `Settings` scene cannot be opened reliably from a menu bar
/// app on macOS 14.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GeneralSettingsSection(model: model)
                SwitchingSettingsSection(model: model)
                ShortcutSettingsSection(model: model)
                cameraSection
                CalibrationsSettingsSection(model: model, openSetup: openSetup)
            }
            .padding(20)
        }
        .frame(width: 520, height: 640)
        .onAppear { model.settingsWindowDidAppear() }
        .onDisappear { model.settingsWindowDidDisappear() }
        .launchGuarded(id: SwayWindowID.settings, model: model)
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera")
                .font(.headline)
            CameraPickerView(model: model)
        }
        .swayCard()
    }

    private func openSetup() {
        model.noteWindowRequested(SwayWindowID.setup)
        openWindow(id: SwayWindowID.setup)
        NSApp.activate()
    }
}

/// Open Sway at login, with the system's "needs approval" state.
private struct GeneralSettingsSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.headline)
            Toggle("Open Sway at login", isOn: binding)
                .toggleStyle(.switch)
                .disabled(unavailableText != nil)
            if model.loginItemStatus == .requiresApproval {
                Text("Allow Sway in System Settings > General > Login Items.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { model.openLoginItemsSettings() }
            }
            if let text = unavailableText {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.loginItemMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(SwayPalette.brick)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .swayCard()
    }

    private var unavailableText: String? {
        if case .unavailable(let text) = model.loginItemStatus { return text }
        return nil
    }

    private var binding: Binding<Bool> {
        Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) })
    }
}

/// Hold time and Switch confidence.
private struct SwitchingSettingsSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switching")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hold time")
                    Spacer()
                    Text(SensitivityPresentation.dwellText(model.sensitivity.dwell))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(get: { model.sensitivity.dwell }, set: { model.setHoldTime($0) }),
                    in: SwitchSensitivity.dwellRange, step: SensitivityPresentation.dwellStep
                ) {
                    Text("Hold time")
                }
                .labelsHidden()
                Text("How long you look at a display before Sway switches to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Switch confidence")
                    Spacer()
                    Text(SensitivityPresentation.confidenceName(model.sensitivity.confidenceLevel))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(model.sensitivity.confidenceLevel) },
                        set: { model.setSwitchConfidence(Int($0.rounded())) }),
                    in: SensitivityPresentation.confidenceRange, step: 1
                ) {
                    Text("Switch confidence")
                } minimumValueLabel: {
                    Text("Relaxed")
                } maximumValueLabel: {
                    Text("Strict")
                }
                .labelsHidden()
                Text("A stricter setting needs a clearer look at one display before Sway switches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Restore Defaults") { model.restoreSensitivityDefaults() }
                .disabled(model.sensitivity == .default)
        }
        .swayCard()
    }
}

/// The Focus Lock shortcut and its recorder.
private struct ShortcutSettingsSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus Lock shortcut")
                .font(.headline)
            HStack {
                Text(shortcutText)
                    .font(.title3.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Focus Lock shortcut")
                    .accessibilityValue(shortcutText)
                Spacer()
                if model.isRecordingShortcut {
                    Button("Cancel") { model.cancelShortcutRecording() }
                } else {
                    Button("Record Shortcut") { model.beginShortcutRecording() }
                }
            }
            HStack {
                Button("Reset to \(HotKeyShortcut.focusLockDefault.displayString)") {
                    model.resetFocusLockShortcut()
                }
                .disabled(model.isRecordingShortcut || model.focusLockShortcut == .focusLockDefault)
                Button("Clear") { model.clearFocusLockShortcut() }
                    .disabled(model.isRecordingShortcut || model.focusLockShortcut == nil)
            }
            if let hint = model.shortcutRecordingHint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(SwayPalette.amber)
            }
            if let message = model.shortcutMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(SwayPalette.brick)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Works from any app. A shortcut needs Control, Option, or Command. Esc cancels recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .swayCard()
    }

    private var shortcutText: String {
        if model.isRecordingShortcut { return "Type a shortcut\u{2026}" }
        return model.focusLockShortcut?.displayString ?? "None"
    }
}

/// The saved calibrations, newest first.
private struct CalibrationsSettingsSection: View {
    let model: AppModel
    let openSetup: () -> Void

    var body: some View {
        let rows = model.calibrationRows
        VStack(alignment: .leading, spacing: 10) {
            Text("Calibrations")
                .font(.headline)
            if rows.isEmpty {
                Text("No calibrations yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                CalibrationRowView(row: row) { model.deleteCalibration(row.key) }
                if row.id != rows.last?.id { Divider() }
            }
            Button("Calibrate\u{2026}", action: openSetup)
        }
        .swayCard()
    }
}

private struct CalibrationRowView: View {
    let row: CalibrationRow
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displays)
                        .fixedSize(horizontal: false, vertical: true)
                    if row.isInUse {
                        Text("In use")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .foregroundStyle(SwayPalette.forest)
                            .background(SwayPalette.sage.opacity(0.35), in: Capsule())
                    }
                }
                Text("\(row.camera) \u{00B7} \(row.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(model: PreviewSupport.model(withProfile: true))
}
#endif
