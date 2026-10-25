import AppKit
import SwayModels
import SwiftUI

/// The menu bar popover (SPEC F19): the status line, at most one banner, the Tracking and Focus Lock switches, the
/// "Looking at" line, the camera picker, and the window shortcuts.
struct MenuContentView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    /// False while the popover is closed; SwiftUI keeps its views alive between openings (`WindowVisibility`).
    @State private var showsLiveContent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            banner
            TrackingToggle(model: model)
            FocusLockToggle(model: model)
            lookLine
            CameraPickerView(model: model)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Calibrate\u{2026}", systemImage: "viewfinder") {
                    open(SwayWindowID.gateTest)
                }
                MenuRow(title: "Pose Debug Window\u{2026}", systemImage: "waveform.path.ecg") {
                    open(SwayWindowID.poseDebug)
                }
                MenuRow(title: "Head-Pose Gate Test\u{2026}", systemImage: "scope") {
                    open(SwayWindowID.gateTest)
                }
                MenuRow(title: "Focus Test Window\u{2026}", systemImage: "rectangle.2.swap") {
                    open(SwayWindowID.focusTest)
                }
                MenuRow(title: "Quit Sway", systemImage: "power") {
                    Task { await model.quit() }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(WindowVisibilityReader { showsLiveContent = $0 })
        .onAppear { refresh() }
        // The popover can stay alive between openings, so refresh whenever a window becomes key too.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        model.refreshEnvironment()
        model.refreshAccessibilityTrust()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sway")
                .font(.headline)
            StatusBadge(model: model, lineLimit: 1)
        }
    }

    /// At most one banner (`MenuBanner`).
    @ViewBuilder
    private var banner: some View {
        switch model.menuBanner {
        case nil:
            EmptyView()
        case .cameraPermission?:
            CameraPermissionView(model: model)
        case .firstSetup?:
            infoBanner(MenuBanner.firstSetupText, systemImage: "wand.and.stars", button: "Set Up\u{2026}") {
                open(SwayWindowID.gateTest)
            }
        case .needsCalibration?:
            infoBanner(
                MenuBanner.needsCalibrationText, systemImage: "questionmark.circle", button: "Calibrate\u{2026}"
            ) {
                open(SwayWindowID.gateTest)
            }
        case .needsAccessibility?:
            infoBanner(MenuBanner.needsAccessibilityText, systemImage: "hand.raised", button: "Grant Access\u{2026}") {
                model.grantAccessibility()
            }
        case .shortcut(let message)?:
            infoBanner(message, systemImage: "keyboard", button: nil) {}
        }
    }

    private func infoBanner(
        _ text: String, systemImage: String, button: String?, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: systemImage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .swayCard()
        .accessibilityElement(children: .contain)
    }

    /// Always exactly one line, so the popover keeps its height when the camera starts or stops. It draws only while
    /// the popover is open, so a closed (but alive) popover never reads the look.
    private var lookLine: some View {
        Text(showsLiveContent ? model.lookSummary.text : LookSummary.off.text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
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
#Preview("Menu, tracking") {
    MenuContentView(model: PreviewSupport.model(tracking: true, withProfile: true))
}

#Preview("Menu, paused") {
    MenuContentView(model: PreviewSupport.model())
}
#endif
