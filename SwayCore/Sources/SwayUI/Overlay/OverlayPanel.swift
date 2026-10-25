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
        isReleasedWhenClosed = false
        level = .screenSaver
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
