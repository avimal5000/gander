import AppKit
import SwayModels
import SwiftUI

/// The menu bar popover (SPEC F1): status line, live toggle, mini readout, camera picker, window shortcuts, quit.
struct MenuContentView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            CameraPermissionView(model: model)
            LiveCameraToggle(model: model)
            miniReadout
            CameraPickerView(model: model)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Pose Debug Window\u{2026}", systemImage: "waveform.path.ecg") {
                    open(SwayWindowID.poseDebug)
                }
                MenuRow(title: "Head-Pose Gate Test\u{2026}", systemImage: "scope") {
                    open(SwayWindowID.gateTest)
                }
                MenuRow(title: "Quit Sway", systemImage: "power") {
                    Task { await model.quit() }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { model.refreshEnvironment() }
        // The popover can stay alive between openings, so refresh whenever a window becomes key too.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshEnvironment()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sway")
                .font(.headline)
            StatusBadge(model: model)
            if model.gateRunState != .idle {
                Text("Gate test in progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var miniReadout: some View {
        if let pose = model.latestSample?.pose {
            HStack(spacing: 16) {
                readout("Yaw", Formatting.degrees(pose.yaw))
                readout("Pitch", Formatting.degrees(pose.pitch))
            }
        } else if model.status.isRunning {
            Text("No face detected")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func readout(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func open(_ id: String) {
        model.noteWindowRequested(id)
        openWindow(id: id)
        NSApp.activate()
    }
}

/// A full-width menu item with a hover highlight.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .onHover { isHovering = $0 }
    }
}

#if DEBUG
#Preview("Menu, camera on") {
    MenuContentView(model: PreviewSupport.model(live: true))
}

#Preview("Menu, camera off") {
    MenuContentView(model: PreviewSupport.model())
}
#endif
