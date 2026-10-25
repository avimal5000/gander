import AppKit
import SwayModels
import SwiftUI

/// The live ``FeedbackPresenting``: one reusable panel for the edge glow and one for the Focus Lock notice.
///
/// The panels are `OverlayPanel`s: borderless, click-through, non-activating, never key or main, above the normal
/// window layer (so focus switching never picks them), on every Space and over full-screen apps. They are created on
/// first use and kept. Between uses they are ordered out, so nothing draws and nothing runs. Fades are window alpha
/// animations: no per-frame work in Sway, and no SwiftUI state to update.
@MainActor
final class FeedbackOverlayController: FeedbackPresenting {
    private var glowPanel: OverlayPanel?
    private var noticePanel: OverlayPanel?
    private var noticeView: NoticePillView?
    /// The sequence that fades the current glow, so a new glow can cancel it.
    private var glowTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private let log = SwayLogger.ui
    /// Finds the screen that shows a display; injected so a test never touches `NSScreen`.
    private let screenFor: @MainActor (DisplayInfo) -> NSScreen?

    init(screenFor: @escaping @MainActor (DisplayInfo) -> NSScreen? = { ScreenMatcher.screen(for: $0) }) {
        self.screenFor = screenFor
    }

    /// True once a panel has been created (they are made on first use).
    var hasPanels: Bool { glowPanel != nil || noticePanel != nil }

    func showGlow(on display: DisplayInfo, animated: Bool) {
        guard let screen = screenFor(display) else {
            log.error("No screen found for the glow on display \(display.cgDisplayID, privacy: .public)")
            return
        }
        let panel = glowPanel ?? makeGlowPanel(on: screen)
        glowPanel = panel
        glowTask?.cancel()
        glowTask = present(panel, frame: screen.frame, timing: .glow, animated: animated)
    }

    func showNotice(_ text: String, symbol: String, on display: DisplayInfo, animated: Bool) {
        guard let screen = screenFor(display) else {
            log.error("No screen found for the notice on display \(display.cgDisplayID, privacy: .public)")
            return
        }
        if noticePanel == nil || noticeView == nil {
            let made = makeNoticePanel()
            noticePanel = made.panel
            noticeView = made.pill
        }
        guard let panel = noticePanel, let pill = noticeView else { return }
        let size = pill.configure(text: text, symbol: symbol)
        noticeTask?.cancel()
        noticeTask = present(
            panel, frame: FeedbackLayout.noticeFrame(size: size, in: screen.visibleFrame), timing: .notice,
            animated: animated)
    }

    // MARK: Panels

    private func makeGlowPanel(on screen: NSScreen) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen, content: EdgeGlowView())
        panel.animationBehavior = .none
        return panel
    }

    private func makeNoticePanel() -> (panel: OverlayPanel, pill: NoticePillView) {
        let pill = NoticePillView()
        let panel = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 160, height: 36), view: pill)
        panel.animationBehavior = .none
        return (panel, pill)
    }

    // MARK: Showing

    /// Puts `panel` at `frame`, fully transparent, in front of everything without activating Sway, then fades it in,
    /// holds, fades it out, and orders it out. Cancelling the returned task stops the sequence where it is.
    private func present(
        _ panel: OverlayPanel, frame: NSRect, timing: FeedbackTiming, animated: Bool
    ) -> Task<Void, Never> {
        Self.setAlpha(of: panel, to: 0, duration: 0)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        return Task { @MainActor in
            // A newer request may have cancelled this one before it began.
            guard !Task.isCancelled else { return }
            if animated {
                Self.setAlpha(of: panel, to: 1, duration: timing.fadeIn)
                guard await Self.pause(timing.fadeIn + timing.hold) else { return }
                Self.setAlpha(of: panel, to: 0, duration: timing.fadeOut)
                guard await Self.pause(timing.fadeOut) else { return }
            } else {
                Self.setAlpha(of: panel, to: 1, duration: 0)
                guard await Self.pause(timing.plainDuration) else { return }
            }
            panel.orderOut(nil)
        }
    }

    /// Sets the panel's opacity over `duration` seconds. A duration of zero is immediate and ends any fade in progress.
    private static func setAlpha(of panel: NSPanel, to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        }
        if duration == 0 { panel.alphaValue = alpha }
    }

    /// Waits `seconds`. False when the task was cancelled meanwhile.
    private static func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }
}
