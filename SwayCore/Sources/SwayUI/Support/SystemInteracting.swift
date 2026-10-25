import AppKit
import Foundation

/// Everything `AppModel` needs from the desktop beyond its own windows. A protocol so tests never open System
/// Settings, show panels, or touch the pasteboard.
@MainActor
protocol SystemInteracting: AnyObject {
    /// Opens System Settings > Privacy & Security > Camera.
    func openCameraPrivacySettings()
    /// Opens System Settings > Privacy & Security > Accessibility.
    func openAccessibilityPrivacySettings()
    /// Selects `url` in a Finder window.
    func revealInFinder(_ url: URL)
    /// Replaces the general pasteboard contents with `string`.
    func copyToPasteboard(_ string: String)
    /// Shows an open panel for a JSON trace, starting in `directory`; `nil` if the user cancels.
    func chooseTraceFile(startingIn directory: URL) -> URL?
    /// Quits the app.
    func terminateApp()
}

/// The real desktop integration.
@MainActor
final class AppKitSystemInteractions: SystemInteracting {
    /// Deep link to the Camera pane of Privacy & Security.
    static let cameraPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    )

    /// Deep link to the Accessibility pane of Privacy & Security.
    static let accessibilityPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    func openCameraPrivacySettings() {
        guard let url = Self.cameraPrivacyURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilityPrivacySettings() {
        guard let url = Self.accessibilityPrivacyURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func chooseTraceFile(startingIn directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Trace"
        panel.message = "Choose a saved Sway pose trace."
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        NSApp.activate()
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func terminateApp() {
        NSApplication.shared.terminate(nil)
    }
}
