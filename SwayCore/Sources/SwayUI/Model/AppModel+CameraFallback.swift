import Foundation
import SwayModels

// The USB camera fallback (SPEC D46, CONTRACT 6.5.5 item 7). When the camera the user chose is unplugged and capture
// stays interrupted for 5 s, Gander restarts the pose source on a connected camera that has a calibration for the
// current displays (the built-in first), and restarts it on the chosen camera once that is connected again. With no
// calibrated camera to use, Gander turns Tracking off in memory (the saved choice stays, as for a camera failure, D23)
// and the status names the missing camera until it is connected again; the user turns Tracking back on. The saved
// camera choice (`selectedCameraID`) is never touched: the stand-in lives in `fallbackCamera` and in the pose source
// configuration alone. Nothing changes while a calibration, the gate test, or the Setup window runs, or while the
// camera is suspended.
extension AppModel {
    /// How long the chosen camera may stay unplugged, with capture interrupted, before a stand-in takes over, in
    /// seconds.
    static let cameraFallbackDelay: TimeInterval = 5

    /// The start that the fallback began, while it runs.
    enum FallbackRestart: Equatable {
        /// On a stand-in, because the chosen camera has been unplugged for long enough.
        case standIn
        /// On the chosen camera, which is connected again. Carries the stand-in it replaces, or `nil` when nothing was
        /// running (a retry after earlier failed starts).
        case chosen(replacing: CameraDevice?)
    }

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

    /// A stand-in that was running and is no longer connected.
    private var unpluggedStandIn: CameraDevice? {
        guard streamTask != nil, let standIn = fallbackCamera, let device = runningDevice, device.id == standIn.id,
            !devices.contains(where: { $0.id == standIn.id })
        else { return nil }
        return device
    }

    /// Capture is interrupted and the camera it runs, the chosen one or its stand-in, is the one that went missing.
    private var isRunningCameraLost: Bool {
        guard case .interrupted = status else { return false }
        return unpluggedChosenCamera != nil || unpluggedStandIn != nil
    }

    /// A start that the fallback began failed because the camera was not ready: nothing runs, Tracking is still on, and
    /// the next device change (or the retry timer) tries again.
    private var isRetryPending: Bool {
        cameraLossElapsed && streamTask == nil && trackingEnabled
    }

    /// Remembers every listed camera's name, so a camera that has gone is still called by it.
    func rememberCameraNames() {
        for device in devices { knownCameraNames[device.id] = device.name }
    }

    /// What the status names as disconnected. With Tracking on, the chosen camera while capture waits for it. With
    /// Tracking off, the chosen camera that Tracking was turned off for, until it is connected again.
    var disconnectedCameraName: String? {
        if !trackingEnabled {
            guard let id = lostCameraID, id == selectedCameraID, !devices.contains(where: { $0.id == id }) else {
                return nil
            }
            return knownCameraNames[id] ?? "The chosen camera"
        }
        return fallbackCamera == nil ? unpluggedChosenCamera?.name : nil
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
        // The camera Tracking was turned off for is back, or the user took over: the status is "Paused" again.
        if lostCameraID != nil, trackingEnabled || isChosenCameraConnected { lostCameraID = nil }
        if fallbackCamera != nil, isChosenCameraConnected {
            cancelCameraLossWait()
            // Never restart the source while the camera is suspended (asleep, locked): that waits for the wake. A switch
            // back that just failed waits for its retry.
            if !isCameraLockedByCalibration, !status.isSuspended, !fallbackSwitchBackDeferred {
                endCameraFallback()
            }
            return
        }
        guard trackingEnabled, isRunningCameraLost || isRetryPending else {
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

    /// The wait is over: restart on a calibrated stand-in, if there is one now. Otherwise nothing is left to use, and
    /// Tracking is turned off.
    private func startCameraFallback() {
        guard trackingEnabled, !isCameraLockedByCalibration, !status.isSuspended else { return }
        if isChosenCameraConnected {
            // Only reached when a start failed and nothing runs: the chosen camera is back, so start on it.
            cancelCameraLossWait()
            refreshActiveCalibration(reconcile: false)
            reconcileForFallback(.chosen(replacing: nil))
            return
        }
        guard let device = fallbackCandidate() else {
            turnTrackingOffForLostCamera()
            return
        }
        cancelCameraLossWait()
        fallbackCamera = device
        log.info("The chosen camera is unplugged; continuing with another calibrated camera")
        // From here the calibration is looked up for the stand-in, and the changed configuration restarts the source.
        refreshActiveCalibration(reconcile: false)
        reconcileForFallback(.standIn)
    }

    /// No connected camera has a calibration for these displays: turn Tracking off, in memory only (the saved choice is
    /// the user's, as for a camera failure, D23), and let the camera go. The status names the chosen camera until it
    /// is connected again, and Tracking stays off until the user turns it on.
    private func turnTrackingOffForLostCamera() {
        guard let id = selectedCameraID else { return }
        log.info("The chosen camera is unplugged and no other camera is calibrated; Tracking is turned off")
        clearCameraFallback()
        lostCameraID = id
        // A failed retry left "failed" on screen; the lost camera is the reason, and the status names it.
        if case .failed = status { status = .stopped }
        trackingEnabled = false
        resetTracking()
        syncTrackingActivity()
        reconcileCamera()
    }

    /// The chosen camera is connected again: restart on it.
    private func endCameraFallback() {
        guard let standIn = fallbackCamera else { return }
        fallbackCamera = nil
        log.info("The chosen camera is connected again")
        refreshActiveCalibration(reconcile: false)
        reconcileForFallback(.chosen(replacing: standIn))
    }

    /// Queues the one reconcile that carries out `restart`, marked as the fallback's own so that a start failing
    /// because the camera is not ready keeps Tracking on. The mark ends with that reconcile, whatever it did.
    private func reconcileForFallback(_ restart: FallbackRestart) {
        fallbackRestart = restart
        fallbackRestartSerial += 1
        let serial = fallbackRestartSerial
        enqueueCameraWork { model in
            await model.performCameraReconcile()
            if model.fallbackRestartSerial == serial { model.fallbackRestart = nil }
        }
    }

    /// A start that the fallback began failed. When the camera was merely not ready to open (`.deviceUnavailable`,
    /// `.noDevice`: a camera just plugged in), Tracking stays on and the fallback tries again later; returns true.
    /// Any other error returns false, and the caller handles it as before.
    func recoverFromFailedFallbackStart() -> Bool {
        guard let restart = fallbackRestart else { return false }
        fallbackRestart = nil
        guard permissionPrompt == nil, case .failed(let error) = status, error.isCameraNotReady else { return false }
        log.info("The camera was not ready to open; Tracking stays on and the fallback tries again")
        switch restart {
        case .chosen(let standIn?):
            // Back on the stand-in, and not tried again at once: every start of the stand-in would trigger it.
            fallbackCamera = standIn
            fallbackSwitchBackDeferred = true
            refreshActiveCalibration(reconcile: false)
            reconcileForFallback(.standIn)
        case .standIn, .chosen(nil):
            // Nothing runs. The 5 s are over, so the next device change (or the retry) starts a camera again.
            fallbackCamera = nil
            cameraLossElapsed = true
        }
        scheduleFallbackRetry()
        return true
    }

    private func scheduleFallbackRetry() {
        fallbackRetryTimer?.cancel()
        fallbackRetryTimer = environment.scheduler.schedule(after: Self.cameraFallbackDelay) { [weak self] in
            self?.fallbackRetryDue()
        }
    }

    private func fallbackRetryDue() {
        fallbackRetryTimer = nil
        fallbackSwitchBackDeferred = false
        syncCameraFallback()
    }

    /// The device list changed: a switch back that failed may work now.
    func deviceListDidChange() {
        fallbackSwitchBackDeferred = false
    }

    /// Forgets the stand-in and the wait: the camera stops, or the user chose a camera. Starts nothing.
    func clearCameraFallback() {
        cancelCameraLossWait()
        fallbackRetryTimer?.cancel()
        fallbackRetryTimer = nil
        fallbackSwitchBackDeferred = false
        fallbackRestart = nil
        if fallbackCamera != nil { fallbackCamera = nil }
    }
}

extension CameraError {
    /// The camera could not be opened right now but may be able to shortly: one just plugged in, or still starting up.
    var isCameraNotReady: Bool {
        switch self {
        case .deviceUnavailable, .noDevice: true
        case .notAuthorized, .configurationFailed, .runtimeFailure: false
        }
    }
}
