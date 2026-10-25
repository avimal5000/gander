import AppKit
import Foundation
import SwayModels

// Observers and shutdown.
extension AppModel {
    /// Watches app termination and deactivation, using the injected notification center.
    func observeApplicationNotifications() {
        let center = environment.notificationCenter
        // Posted on the main thread by AppKit; with no queue the block runs synchronously on the poster.
        let terminate = center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
        let resign = center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidResignActive() }
        }
        let become = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.applicationDidBecomeActive() }
        }
        // Any of Sway's windows (the menu included) gaining or losing key status. Closing Sway's last window leaves it
        // active with nothing in front, which must release the hold.
        let windowKeyChanges = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                let resigned = notification.name == NSWindow.didResignKeyNotification
                let window = notification.object as? NSWindow
                MainActor.assumeIsolated { self?.windowKeyStatusChanged(window, resigned: resigned) }
            }
        }
        // Another app came to the front: ask where focus is now. Posted on the main thread by AppKit.
        let activation = environment.workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFocusedDisplay() }
        }
        // A camera connected or disconnected (a late USB camera at login, a dock unplugged): the camera capture would
        // pick, and so the calibration that fits, may have changed. AVFoundation's notification names, spelled out
        // because this module does not import AVFoundation; they may arrive on any thread.
        let cameraChanges = ["AVCaptureDeviceWasConnectedNotification", "AVCaptureDeviceWasDisconnectedNotification"]
            .map { name in
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshEnvironment() }
                }
            }
        notificationObservers = [terminate, resign, become] + windowKeyChanges + cameraChanges
        workspaceObservers = [activation]
    }

    /// Follows the display layout; a change during a gate test cancels it.
    func observeDisplayLayouts() {
        let stream = displays.layouts()
        layoutTask = Task { [weak self] in
            for await layout in stream {
                guard let self else { return }
                self.layoutDidChange(layout)
            }
        }
    }

    func layoutDidChange(_ newLayout: DisplayLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        displayLabels = DisplayLabeler.labels(for: newLayout)
        // Display identities may have changed, so a dwell or the believed focus no longer means anything. A changed
        // calibration rebuilds the decider; an unchanged one still needs its targets and a clean loop.
        if !refreshActiveCalibration() {
            updateTrackedTargets()
            resetTracking()
            if isPollingFocus { pollFocusedDisplay() }
        }
        if gateRunState != .idle {
            let noun = gatePurpose.noun
            cancelRunningGate(reason: "The display arrangement changed, so the \(noun) was cancelled.")
        }
    }

    /// A window of Sway became or stopped being key. Re-reads whether Sway is in front, and ends a shortcut recording
    /// when the Settings window it belongs to lost key status (the recorder listens to this window only).
    func windowKeyStatusChanged(_ window: NSWindow?, resigned: Bool) {
        refreshSwayInFront()
        if resigned, isRecordingShortcut, let window, windowRefs[SwayWindowID.settings]?.window === window {
            cancelShortcutRecording()
        }
    }

    /// Sway became the active app; automatic switching holds while its menu or a window is in front.
    func applicationDidBecomeActive() {
        refreshSwayInFront()
        // Back from System Settings: a permission the Setup window waits for may have been granted, and a login item
        // approval may have been given.
        if setupFlow?.isPermissionStep == true { setupTick() }
        if settingsVisible { refreshLoginItemStatus() }
    }

    /// Re-reads whether Sway is in front, assigning only on a change.
    func refreshSwayInFront() {
        let inFront = environment.isAppActive()
        if inFront != isAppActive { isAppActive = inFront }
    }

    /// The overlays hide the gate window, so Esc is the way out; if the app loses focus Esc stops working and the
    /// test is no longer meaningful, so cancel it.
    func applicationDidResignActive() {
        refreshSwayInFront()
        guard gateRunState == .running else { return }
        let noun = gatePurpose.noun
        cancelRunningGate(reason: "The \(noun) was cancelled because Sway was no longer the active app.")
    }

    /// Best effort at quit: close overlays and ask the camera to stop. The process exiting also ends capture.
    ///
    /// Tracking is turned off in memory only: the saved choice (`sway.trackingEnabled`) is the user's, so the next
    /// launch restores it.
    func applicationWillTerminate() {
        if gateRunState != .idle {
            gateSession?.cancel()
            endGate(message: nil)
        }
        closeSetup()
        cancelShortcutRecording()
        trackingEnabled = false
        resetTracking()
        streamTask?.cancel()
        streamTask = nil
        syncTrackingActivity()
        stopFocusTest()
        let poseSource = poseSource
        let camera = camera
        Task {
            await poseSource.stop()
            await camera.stop()
        }
    }

    /// Stops the gate test and the camera and waits until the camera is off.
    func shutdown() async {
        if gateRunState != .idle {
            gateSession?.cancel()
            endGate(message: nil)
        }
        closeSetup()
        cancelShortcutRecording()
        trackingEnabled = false
        layoutTask?.cancel()
        stopFocusTest()
        await reconcileCamera().value
        await camera.stop()
    }

    /// Menu "Quit Sway": switch the camera off first so the indicator goes dark, then terminate.
    func quit() async {
        await shutdown()
        environment.system.terminateApp()
    }
}
