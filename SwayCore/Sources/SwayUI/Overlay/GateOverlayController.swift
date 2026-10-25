import AppKit
import SwayModels
import SwiftUI

/// Presents one overlay panel on the screen of the display the user should look at, and moves it from screen to
/// screen as the gate test advances. Panels are created lazily per display, faded in and out with SwiftUI, and
/// always closed by `dismiss()`.
@MainActor
final class GateOverlayController: GateOverlayPresenting {
    private struct Entry {
        let panel: OverlayPanel
        let model: GateOverlayModel
    }

    var onCancelRequested: (@MainActor () -> Void)?

    private var entries: [DisplayID: Entry] = [:]
    private let escapeMonitor = EscapeKeyMonitor()
    private let log = SwayLogger.ui

    func canPresent(on display: DisplayInfo) -> Bool {
        ScreenMatcher.screen(for: display) != nil
    }

    func present(_ progress: GateProgress) {
        installEscapeMonitor()
        let target = progress.display
        for id in entries.keys where id != target.id {
            fadeOutAndClose(id)
        }
        if let entry = entries[target.id] {
            entry.model.progress = progress
            entry.model.isVisible = true
            return
        }
        guard let screen = ScreenMatcher.screen(for: target) else {
            log.error("No screen found for display \(target.cgDisplayID, privacy: .public)")
            return
        }
        let model = GateOverlayModel(progress: progress)
        let panel = OverlayPanel(screen: screen, content: GateOverlayView(model: model))
        entries[target.id] = Entry(panel: panel, model: model)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        escapeMonitor.remove()
        for id in Array(entries.keys) {
            fadeOutAndClose(id)
        }
    }

    private func installEscapeMonitor() {
        escapeMonitor.install { [weak self] in
            self?.onCancelRequested?()
        }
    }

    /// Fades the panel's content out, then removes the panel once the fade is done.
    private func fadeOutAndClose(_ id: DisplayID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.model.isVisible = false
        let panel = entry.panel
        let delay = Duration.seconds(GateOverlayView.fadeDuration + 0.05)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            panel.orderOut(nil)
            panel.close()
        }
    }
}
