import Foundation
import SwayModels

@testable import SwayUI

/// Records desktop interactions instead of performing them.
@MainActor
final class FakeSystem: SystemInteracting {
    private(set) var openedSettingsCount = 0
    private(set) var openedAccessibilitySettingsCount = 0
    private(set) var revealed: [URL] = []
    private(set) var copied: [String] = []
    private(set) var terminateCount = 0
    private(set) var chooserDirectories: [URL] = []
    var chosenFile: URL?

    func openCameraPrivacySettings() { openedSettingsCount += 1 }
    func openAccessibilityPrivacySettings() { openedAccessibilitySettingsCount += 1 }
    func revealInFinder(_ url: URL) { revealed.append(url) }
    func copyToPasteboard(_ string: String) { copied.append(string) }
    func terminateApp() { terminateCount += 1 }

    func chooseTraceFile(startingIn directory: URL) -> URL? {
        chooserDirectories.append(directory)
        return chosenFile
    }
}

/// Records overlay calls instead of showing panels.
@MainActor
final class FakeOverlay: GateOverlayPresenting {
    var onCancelRequested: (@MainActor () -> Void)?
    /// Display IDs that have no screen.
    var unavailable: Set<DisplayID> = []
    private(set) var presented: [GateProgress] = []
    private(set) var dismissCount = 0
    private(set) var isShowing = false

    var lastProgress: GateProgress? { presented.last }

    func canPresent(on display: DisplayInfo) -> Bool {
        !unavailable.contains(display.id)
    }

    func present(_ progress: GateProgress) {
        presented.append(progress)
        isShowing = true
    }

    func dismiss() {
        dismissCount += 1
        isShowing = false
    }

    /// Simulates the user pressing Esc.
    func pressEscape() {
        onCancelRequested?()
    }
}
