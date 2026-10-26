import AVFoundation

/// Center Stage would reframe the picture while the user moves, shifting the head pose against the calibration
/// (SPEC D47). Sway takes control of the feature for its own process and switches it off.
enum CenterStageControl {
    /// A static initializer runs exactly once per process, on whichever thread gets there first.
    private static let turnedOff: Void = {
        // Order matters: the enabled flag can only be set in app-control mode.
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
    }()

    /// Switches Center Stage off the first time it is called in this process; later calls do nothing.
    static func turnOffOnce() {
        _ = turnedOff
    }
}
