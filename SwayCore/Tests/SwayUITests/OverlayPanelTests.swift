import AppKit
import SwiftUI
import Testing

@testable import SwayUI

/// What every overlay must stay (CONTRACT 6.5, 6.5.4): if one could become key or activate Gander, each glow would put
/// "Gander in front" on hold and switching would stop without a word. The panels are made here and never shown.
@MainActor
@Suite("Overlay panels never take focus")
struct OverlayPanelTests {
    private func expectOverlay(_ panel: OverlayPanel, _ comment: Comment) {
        #expect(!panel.canBecomeKey && !panel.canBecomeMain, comment)
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless), comment)
        #expect(panel.ignoresMouseEvents, comment)
        #expect(panel.level == .screenSaver, comment)
        #expect(!panel.hidesOnDeactivate && !panel.isOpaque && !panel.hasShadow, comment)
        #expect(
            panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle], comment)
        #expect(!panel.isVisible, comment)
    }

    @Test func aPanelForAViewIsAnOverlay() {
        let panel = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 10, height: 10), view: NSView())
        expectOverlay(panel, "init(frame:view:)")
    }

    @Test func aPanelForAScreenIsAnOverlay() throws {
        let screen = try #require(NSScreen.screens.first, "This test needs a screen; it does not show anything on it")
        let panel = OverlayPanel(screen: screen, content: Color.clear)
        expectOverlay(panel, "init(screen:content:)")
        #expect(panel.frame == screen.frame)
    }
}
