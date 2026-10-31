import AppKit
import SwiftUI

/// A borderless, click-through panel that covers one screen without taking focus (CONTRACT 6.5).
final class OverlayPanel: NSPanel {
    /// Creates a panel exactly covering `screen`, hosting `content`.
    @MainActor
    convenience init(screen: NSScreen, content: some View) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        configureAsOverlay()
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        setFrame(screen.frame, display: false)
    }

    /// Creates a panel at `frame` (global screen coordinates) showing `view` as it is: for overlays that are not a
    /// full screen, and that need AppKit content.
    @MainActor
    convenience init(frame: NSRect, view: NSView) {
        self.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureAsOverlay()
        contentView = view
        setFrame(frame, display: false)
    }

    /// What every overlay is: transparent and above the normal window layer on every Space and over full-screen apps,
    /// ignoring the mouse, and never taking focus.
    @MainActor
    private func configureAsOverlay() {
        isReleasedWhenClosed = false
        level = .screenSaver
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
