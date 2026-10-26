import Foundation
import SwayModels

// The USB camera fallback (SPEC D46, CONTRACT 6.5.5 item 7). When the camera the user chose is unplugged and capture
// stays interrupted for 5 s, Sway restarts the pose source on a connected camera that has a calibration for the
// current displays (the built-in first), and restarts it on the chosen camera once that is connected again. With no
// calibrated stand-in it keeps waiting, and the status says which camera is missing. The saved camera choice
// (`selectedCameraID`) is never touched: the stand-in lives in `fallbackCamera` and in the pose source configuration
// alone. Cameras are never swapped while a calibration, the gate test, or the Setup window runs.
extension AppModel {
    /// How long the chosen camera may stay unplugged, with capture interrupted, before a stand-in takes over, in
    /// seconds.
    static let cameraFallbackDelay: TimeInterval = 5

    // MARK: State

    /// The camera the user chose, when it was the one running in this session and is no longer connected. `nil` for a
    /// default choice, and when capture runs a camera it picked on its own (a chosen camera that was never connected).
    var unpluggedChosenCamera: CameraDevice? {
        guard streamTask != nil, let id = selectedCameraID, let device = runningDevice, device.id == id,
            !devices.contains(where: { $0.id == id })
        else { return nil }
        return device
    }

    /// True when a calibration, the gate test, or the Setup window is open: the camera must not change then.
    private var isCameraLockedByCalibration: Bool {
        gateRunState != .idle || setupFlow != nil
    }

    /// True when the chosen camera is among the connected devices. A default choice counts as connected.
    private var isChosenCameraConnected: Bool {
        guard let id = selectedCameraID else { return true }
        return devices.contains { $0.id == id }
    }

    /// A connected camera other than the chosen one that has a calibration for the current displays: the built-in if
    /// it qualifies, else the first listed.
    func fallbackCandidate() -> CameraDevice? {
        let usable = devices.filter {
            $0.id != selectedCameraID && library.resolve(for: layout, cameraName: $0.name) != nil
        }
        return usable.first(where: \.isBuiltIn) ?? usable.first
    }

    // MARK: Keeping in step

    /// Brings the fallback in line with the camera state. Idempotent and cheap: called whenever the capture status, the
    /// device list, the calibrations, the displays, or a calibration or Setup run changes.
    func syncCameraFallback() {
        if fallbackCamera != nil {
            cancelCameraLossWait()
            // Never restart the source while the camera is suspended (asleep, locked): that waits for the wake.
            if isChosenCameraConnected, !isCameraLockedByCalibration, !status.isSuspended { endCameraFallback() }
            return
        }
        guard case .interrupted = status, unpluggedChosenCamera != nil else {
            cancelCameraLossWait()
            return
        }
        if cameraLossElapsed {
            startCameraFallback()
        } else if cameraLossTimer == nil {
            cameraLossTimer = environment.scheduler.schedule(after: Self.cameraFallbackDelay) { [weak self] in
                self?.cameraLossWaitElapsed()
            }
        }
    }

    private func cameraLossWaitElapsed() {
        cameraLossTimer = nil
        cameraLossElapsed = true
        syncCameraFallback()
    }

    private func cancelCameraLossWait() {
        cameraLossTimer?.cancel()
        cameraLossTimer = nil
        cameraLossElapsed = false
    }

    /// The wait is over: restart on a calibrated stand-in, if there is one now. Otherwise keep waiting, and try again
    /// whenever something changes.
    private func startCameraFallback() {
        guard trackingEnabled, !isCameraLockedByCalibration, let device = fallbackCandidate() else { return }
        cancelCameraLossWait()
        fallbackCamera = device
        log.info("The chosen camera is unplugged; continuing with another calibrated camera")
        // From here the calibration is looked up for the stand-in, and the changed configuration restarts the source.
        refreshActiveCalibration()
        reconcileCamera()
    }

    /// The chosen camera is connected again: restart on it.
    private func endCameraFallback() {
        fallbackCamera = nil
        log.info("The chosen camera is connected again")
        refreshActiveCalibration()
        reconcileCamera()
    }

    /// Forgets the stand-in and the wait: the camera stops, or the user chose a camera. Starts nothing.
    func clearCameraFallback() {
        cancelCameraLossWait()
        if fallbackCamera != nil { fallbackCamera = nil }
    }
}
