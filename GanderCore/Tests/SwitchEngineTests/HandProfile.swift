import Foundation
import GanderModels

/// A small hand-made profile whose numbers are easy to work with in the state machine tests.
///
/// Three displays on one pitch line (pitch 8), yaw 60 / 40 / 0, `yawScale` 2, `pitchScale` 4. Along that line,
/// between display A (60) and display B (40) the nearest display and margin are easy to read off: a pose at
/// yaw `50 + 10 m` is nearest A with margin `m` (runner-up B). The elsewhere box under the default settings is
/// yaw -20...80 and pitch -7...23.
enum HandProfile {
    static let a: DisplayID = "A"
    static let b: DisplayID = "B"
    static let c: DisplayID = "C"

    static let profile = CalibrationProfile(
        features: .visionAngles,
        displays: [
            DisplayProfile(displayID: a, yaw: 60, pitch: 8, yawStd: 1, pitchStd: 1, sampleCount: 100),
            DisplayProfile(displayID: b, yaw: 40, pitch: 8, yawStd: 1, pitchStd: 1, sampleCount: 100),
            DisplayProfile(displayID: c, yaw: 0, pitch: 8, yawStd: 1, pitchStd: 1, sampleCount: 100),
        ],
        yawScale: 2,
        pitchScale: 4,
        layoutFingerprint: "hand",
        cameraName: nil,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    /// Yaw at each display's center (margin 1).
    static let yawA = 60.0
    static let yawB = 40.0
    static let yawC = 0.0
    /// Nearest A with margin 0.2: between `stayMargin` (0.15) and `enterMargin` (0.30).
    static let yawWeakA = 52.0
    /// Nearest A with margin 0.1: below `stayMargin`.
    static let yawVeryWeakA = 51.0
    /// Far outside the elsewhere box.
    static let yawElsewhere = 100.0

    /// Defaults with a binary-exact dwell (0.5 s), so timestamps on a 0.125 s grid compare exactly.
    static let settings: SwitchSettings = {
        var settings = SwitchSettings.default
        settings.dwell = 0.5
        return settings
    }()
}
