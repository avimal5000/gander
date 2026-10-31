import Foundation
import GanderModels

/// Classifies one pose against a calibration profile (CONTRACT section 6.6, "Classification").
///
/// The decision is nearest calibrated display center in axis-scale units (SPEC D18), with an "elsewhere" box
/// around all display centers for looks at the keyboard or away. The constructor precomputes the box, so a
/// classifier is cheap to call at the camera frame rate.
struct PoseClassifier: Sendable {
    let profile: CalibrationProfile
    let settings: SwitchSettings

    /// The elsewhere box: the extent of the display means, grown by the settings' margins. Plain bounds rather
    /// than ranges, so unusual (negative) margins can never trap.
    private let minYaw: Double
    private let maxYaw: Double
    private let minPitch: Double
    private let maxPitch: Double

    init(profile: CalibrationProfile, settings: SwitchSettings) {
        self.profile = profile
        self.settings = settings
        let yaws = profile.displays.map(\.yaw)
        let pitches = profile.displays.map(\.pitch)
        minYaw = (yaws.min() ?? 0) - settings.elsewhereYawMargin
        maxYaw = (yaws.max() ?? 0) + settings.elsewhereYawMargin
        minPitch = (pitches.min() ?? 0) - settings.elsewherePitchMargin
        maxPitch = (pitches.max() ?? 0) + settings.elsewherePitchMargin
    }

    /// Classifies `pose` (`nil` means no face).
    ///
    /// Edge cases the fitter never produces but a hand-built or decoded profile can: no displays gives
    /// `.noFace` (there is nothing to be nearest to), and a single display gives `runnerUp == nil` and
    /// `margin == 0` (nothing to compare against, so never confident enough to switch).
    func classify(_ pose: HeadPose?) -> PoseClassification {
        // Step 1: no usable face.
        guard let pose, pose.faceConfidence >= settings.minFaceConfidence,
            let point = profile.features.point(of: pose), !profile.displays.isEmpty
        else {
            return .noFace
        }

        // Step 2: normalized distance to every display.
        let distances = profile.displays.map { display in
            let dx = (point.x - display.yaw) / profile.yawScale
            let dy = (point.y - display.pitch) / profile.pitchScale
            return (dx * dx + dy * dy).squareRoot()
        }
        var byDisplay: [DisplayID: Double] = [:]
        for (display, distance) in zip(profile.displays, distances) {
            byDisplay[display.displayID] = distance
        }

        // Step 3: best and runner-up. Strict comparisons keep the earlier display on ties.
        var best = 0
        var runnerUp: Int?
        for index in distances.indices.dropFirst() {
            if distances[index] < distances[best] {
                runnerUp = best
                best = index
            } else if let current = runnerUp {
                if distances[index] < distances[current] { runnerUp = index }
            } else {
                runnerUp = index
            }
        }
        let bestID = profile.displays[best].displayID
        let runnerUpID = runnerUp.map { profile.displays[$0].displayID }
        var margin = 0.0
        if let runnerUp {
            let sum = distances[runnerUp] + distances[best]
            margin = sum == 0 ? 0 : (distances[runnerUp] - distances[best]) / sum
        }

        // Step 4: outside the box around all display centers.
        if point.x < minYaw || point.x > maxYaw || point.y < minPitch || point.y > maxPitch {
            return PoseClassification(
                kind: .elsewhere, best: bestID, runnerUp: runnerUpID, margin: 0, distances: byDisplay)
        }

        // Step 5.
        return PoseClassification(
            kind: .display, best: bestID, runnerUp: runnerUpID, margin: margin, distances: byDisplay)
    }
}
