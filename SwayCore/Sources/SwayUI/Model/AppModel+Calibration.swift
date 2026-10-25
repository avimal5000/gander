import Foundation
import SwayModels

// The calibration library (SPEC D25): every saved calibration per display set and camera. Every successful fit (the
// gate test and an opened trace today, the Setup window in M5) saves into it; the active calibration is the one that
// fits the connected displays and the camera, and tracking waits when none does.
extension AppModel {
    // MARK: Fitting

    /// Fits a profile from `trace` and saves it in the library.
    ///
    /// Live tracking has Vision angles only (landmarks are gate-test-only), so the profile always uses them. A
    /// failed fit leaves the library unchanged and explains the problem in `calibrationMessage`.
    func refitCalibration(from trace: PoseTrace) {
        do {
            let profile = try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil)
            calibrationMessage = nil
            lastFittedProfile = profile
            saveToLibrary(profile)
        } catch let error as CalibrationError {
            log.info("Calibration fit failed: \(String(describing: error), privacy: .public)")
            calibrationMessage = .error(error.userMessage)
        } catch {
            log.error("Calibration fit failed: \(String(describing: error), privacy: .public)")
            calibrationMessage = .error(error.localizedDescription)
        }
    }

    /// Saves `profile` as the newest in the library, persists it, and re-resolves the active calibration.
    func saveToLibrary(_ profile: CalibrationProfile) {
        var updated = library
        updated.save(profile)
        guard updated != library else { return }
        library = updated
        persistLibrary()
        refreshActiveCalibration()
    }

    /// Removes the calibration saved under `key` (M5's Settings list).
    func removeFromLibrary(_ key: CalibrationKey) {
        var updated = library
        updated.remove(key)
        guard updated != library else { return }
        library = updated
        persistLibrary()
        refreshActiveCalibration()
    }

    // MARK: Resolution

    /// The name of the camera the calibration is looked up for: the running camera, else the one capture would pick
    /// (CONTRACT 6.1: the selected device if connected, else the first built-in, else the first device).
    var trackingCameraName: String? {
        if let running = status.device?.name { return running }
        return devices.first { $0.id == selectedCameraID }?.name
            ?? devices.first(where: \.isBuiltIn)?.name
            ?? devices.first?.name
    }

    /// Re-resolves the active calibration for the current layout, camera, and library. When it changes, the decider
    /// is rebuilt, and the camera is reconciled if a calibration appeared or disappeared while Tracking is on.
    /// - Parameter reconcile: false at launch, where the launch reconcile follows anyway.
    /// - Returns: true if the active calibration changed.
    @discardableResult
    func refreshActiveCalibration(reconcile: Bool = true) -> Bool {
        let resolved = library.resolve(for: layout, cameraName: trackingCameraName)
        guard resolved != activeCalibration else { return false }
        let appearedOrDisappeared = (resolved == nil) != (activeCalibration == nil)
        activeCalibration = resolved
        rebuildDecider()
        syncTrackingActivity()
        if reconcile, trackingEnabled, appearedOrDisappeared { reconcileCamera() }
        return true
    }

    // MARK: Persistence

    func persistLibrary() {
        do {
            defaults.set(try Self.encoder().encode(library), forKey: DefaultsKey.calibrationLibrary)
            defaults.removeObject(forKey: DefaultsKey.calibrationProfile)
        } catch {
            log.error("Saving the calibrations failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The stored library, with the single profile an earlier version kept migrated into it when the library key is
    /// absent. Data that does not decode, or has another format version, gives an empty library.
    static func storedLibrary(in defaults: UserDefaults) -> (library: CalibrationLibrary, migrated: Bool) {
        let decoder = Self.decoder()
        if let data = defaults.data(forKey: DefaultsKey.calibrationLibrary) {
            return ((try? decoder.decode(CalibrationLibrary.self, from: data)) ?? CalibrationLibrary(), false)
        }
        guard let data = defaults.data(forKey: DefaultsKey.calibrationProfile),
            let profile = try? decoder.decode(CalibrationProfile.self, from: data),
            profile.formatVersion == CalibrationProfile.currentFormatVersion
        else { return (CalibrationLibrary(), false) }
        return (CalibrationLibrary(profiles: [profile]), true)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
