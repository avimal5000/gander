import Foundation

// The camera's grace after a display change (SPEC section 6, CONTRACT 6.5.5 item 6). Unplugging a display, or a dock
// bringing its displays back one at a time, can leave no calibration that fits for a moment. Turning the camera off at
// once and on again a second later would blink its light, so the camera stays for up to 2 s and the stop is cancelled
// if the layout recovers. Only a display change gets this grace: Tracking off, Pause, quit, and lock stop the camera at
// once.
extension AppModel {
    /// How long the camera stays on after a display change left no calibration that fits, in seconds.
    static let cameraGraceDelay: TimeInterval = 2

    /// True while a stop is waiting out its grace.
    var isCameraGraceActive: Bool { cameraGraceTimer != nil }

    /// A display change just took away the calibration the running camera was started for: stop it in
    /// ``cameraGraceDelay`` seconds instead of at once, unless the layout recovers first.
    func beginCameraGrace() {
        guard trackingEnabled, streamTask != nil, !wantsCamera, cameraGraceTimer == nil else { return }
        cameraGraceTimer = environment.scheduler.schedule(after: Self.cameraGraceDelay) { [weak self] in
            self?.cameraGraceExpired()
        }
    }

    /// The layout recovered, or the camera stops for another reason: there is nothing left to wait for.
    func cancelCameraGrace() {
        cameraGraceTimer?.cancel()
        cameraGraceTimer = nil
    }

    private func cameraGraceExpired() {
        cameraGraceTimer = nil
        // The reconcile stops the camera unless a calibration fits again by now.
        reconcileCamera()
    }
}
