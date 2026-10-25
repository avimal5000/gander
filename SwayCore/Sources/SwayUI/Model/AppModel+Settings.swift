import Foundation
import SwayModels

// The Sway Settings window (SPEC F21, D31, D33): the login item, the switching sensitivity, the Focus Lock shortcut
// and its recorder, and the list of saved calibrations. The sensitivity and the shortcut themselves are saved and
// applied by `setSensitivity(_:)` (`AppModel+Tracking`) and `setFocusLockShortcut(_:)` (`AppModel+FocusLock`).
extension AppModel {
    // MARK: Window lifecycle

    /// The Settings window appeared. Ignored for the copy SwiftUI opens at launch, which the launch guard closes
    /// unseen (nobody asked for it).
    func settingsWindowDidAppear() {
        guard hasWindowRequest(SwayWindowID.settings) else { return }
        settingsVisible = true
        refreshEnvironment()
        loginItemMessage = nil
        refreshLoginItemStatus()
    }

    /// The Settings window closed: a shortcut recording ends, and the previous shortcut is registered again.
    func settingsWindowDidDisappear() {
        settingsVisible = false
        cancelShortcutRecording()
    }

    // MARK: General: the login item

    /// True when Sway opens at login, including while the system still waits for the user's approval.
    var opensAtLogin: Bool {
        switch loginItemStatus {
        case .enabled, .requiresApproval: true
        case .disabled, .unavailable: false
        }
    }

    /// Re-reads the login item from the system, assigning only on a change.
    func refreshLoginItemStatus() {
        let current = loginItem.status
        if current != loginItemStatus { loginItemStatus = current }
    }

    /// The "Open Sway at login" toggle. A failure keeps the toggle where the system left it and says why.
    func setOpensAtLogin(_ enabled: Bool) {
        loginItemMessage = nil
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            loginItemMessage = error.message
        }
        refreshLoginItemStatus()
    }

    /// "Open Login Items": System Settings > General > Login Items.
    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    // MARK: Switching

    /// The Hold time slider: seconds on the 0.05 s grid, inside the allowed range.
    func setHoldTime(_ seconds: Double) {
        setSensitivity(
            SwitchSensitivity(
                dwell: SensitivityPresentation.snappedDwell(seconds), confidenceLevel: sensitivity.confidenceLevel))
    }

    /// The Switch confidence slider: 0 (Relaxed) to 4 (Strict).
    func setSwitchConfidence(_ level: Int) {
        setSensitivity(SwitchSensitivity(dwell: sensitivity.dwell, confidenceLevel: level))
    }

    /// "Restore Defaults".
    func restoreSensitivityDefaults() {
        setSensitivity(.default)
    }

    // MARK: Focus Lock shortcut

    /// "Record Shortcut": listens for one key press in Sway's own windows. The current shortcut is unregistered while
    /// recording, so pressing it again cannot toggle Focus Lock.
    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutRecordingHint = nil
        hotKeys.unregister(.toggleFocusLock)
        isShortcutRegistered = false
        environment.keyMonitor.start { [weak self] press in
            self?.handleRecordedKey(press) ?? false
        }
    }

    /// One key press while recording. Every press is consumed, so typing a shortcut never triggers a menu command.
    /// - Returns: whether the press was consumed.
    @discardableResult
    func handleRecordedKey(_ press: ShortcutKeyPress) -> Bool {
        guard isRecordingShortcut else { return false }
        switch ShortcutMapping.capture(press) {
        case .cancel:
            cancelShortcutRecording()
        case .invalid:
            shortcutRecordingHint = ShortcutMapping.invalidMessage
        case .shortcut(let shortcut):
            endShortcutRecording()
            // The new shortcut is registered first; if another app has it, the previous one stays and the message
            // says why (`shortcutMessage`).
            setFocusLockShortcut(shortcut)
        }
        return true
    }

    /// Stops recording (Esc, the Cancel button, the window closing or losing key status) and registers the previous
    /// shortcut again. Does nothing when not recording.
    func cancelShortcutRecording() {
        guard isRecordingShortcut else { return }
        endShortcutRecording()
        registerFocusLockShortcut()
    }

    private func endShortcutRecording() {
        environment.keyMonitor.stop()
        isRecordingShortcut = false
        shortcutRecordingHint = nil
    }

    /// "Reset to ⌃⌥⌘L".
    func resetFocusLockShortcut() {
        setFocusLockShortcut(.focusLockDefault)
    }

    /// "Clear": no Focus Lock shortcut.
    func clearFocusLockShortcut() {
        setFocusLockShortcut(nil)
    }

    // MARK: Calibrations

    /// The saved calibrations, newest first, with the one in use marked.
    var calibrationRows: [CalibrationRow] {
        CalibrationListPresentation.rows(
            library: library, activeKey: activeCalibration?.saved.key, name: { displayName(for: $0) })
    }

    /// "Delete" on a row. Calibrating again restores it.
    func deleteCalibration(_ key: CalibrationKey) {
        removeFromLibrary(key)
    }
}
