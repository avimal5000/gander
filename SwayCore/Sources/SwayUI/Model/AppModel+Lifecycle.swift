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
        notificationObservers = [terminate, resign]
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
        if gateRunState != .idle {
            cancelGateTest(reason: "The display arrangement changed, so the gate test was cancelled.")
        }
    }

    /// The overlays hide the gate window, so Esc is the way out; if the app loses focus Esc stops working and the
    /// test is no longer meaningful, so cancel it.
    func applicationDidResignActive() {
        guard gateRunState == .running else { return }
        cancelGateTest(reason: "The gate test was cancelled because Sway was no longer the active app.")
    }

    /// Best effort at quit: close overlays and ask the camera to stop. The process exiting also ends capture.
    func applicationWillTerminate() {
        if gateRunState != .idle {
            gateSession?.cancel()
            endGate(message: nil)
        }
        liveEnabled = false
        streamTask?.cancel()
        streamTask = nil
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
        liveEnabled = false
        layoutTask?.cancel()
        await reconcileCamera().value
        await camera.stop()
    }

    /// Menu "Quit Sway": switch the camera off first so the indicator goes dark, then terminate.
    func quit() async {
        await shutdown()
        environment.system.terminateApp()
    }
}
