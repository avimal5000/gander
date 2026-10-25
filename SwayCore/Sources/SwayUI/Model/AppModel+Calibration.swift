import Foundation
import SwayModels

// The calibration profile (SPEC F10, D17): until guided calibration arrives, the gate test is the calibration. After
// every analysis, and every opened trace, the engine fits a Vision-angles profile that is kept in `UserDefaults`.
extension AppModel {
    /// True when displays were added, removed, or moved since the profile was fitted (or its format is outdated).
    var isCalibrationStale: Bool {
        guard let profile = calibrationProfile else { return false }
        return !profile.matches(layout)
    }

    /// Fits a profile from `trace` and makes it the calibration.
    ///
    /// Live tracking has Vision angles only (landmarks are gate-test-only), so the profile always uses them. A
    /// failed fit keeps the previous profile and explains the problem in `calibrationMessage`.
    func refitCalibration(from trace: PoseTrace) {
        do {
            let profile = try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
            calibrationMessage = nil
            adoptCalibration(profile)
        } catch let error as CalibrationError {
            log.info("Calibration fit failed: \(String(describing: error), privacy: .public)")
            calibrationMessage = .error(error.userMessage)
        } catch {
            log.error("Calibration fit failed: \(String(describing: error), privacy: .public)")
            calibrationMessage = .error(error.localizedDescription)
        }
    }

    /// Stores `profile` as the calibration and restarts the preview's decider on it.
    private func adoptCalibration(_ profile: CalibrationProfile) {
        persist(profile)
        guard profile != calibrationProfile else { return }
        calibrationProfile = profile
        rebuildDecider()
    }

    private func persist(_ profile: CalibrationProfile) {
        do {
            defaults.set(try Self.profileEncoder().encode(profile), forKey: DefaultsKey.calibrationProfile)
        } catch {
            log.error("Saving the calibration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The stored profile, or `nil` when there is none, it does not decode, or it has another `formatVersion`
    /// (such a profile is refitted by the next gate test, never reused).
    static func storedCalibrationProfile(in defaults: UserDefaults) -> CalibrationProfile? {
        guard let data = defaults.data(forKey: DefaultsKey.calibrationProfile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let profile = try? decoder.decode(CalibrationProfile.self, from: data),
            profile.formatVersion == CalibrationProfile.currentFormatVersion
        else { return nil }
        return profile
    }

    private static func profileEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
