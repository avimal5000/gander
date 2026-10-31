import Foundation
import GanderModels

// The calibration library (SPEC D25): every saved calibration per display set and camera. Every successful fit (the
// gate test, an opened trace, and the Setup window) saves into it; the active calibration is the one that
// fits the connected displays and the camera, and tracking waits when none does.
extension AppModel {
    // MARK: Fitting

    /// Why a fit failed, in words for the user.
    struct FitFailure: Error, Equatable {
        let text: String
    }

    /// Fits a profile from `trace` and saves it in the library.
    ///
    /// Live tracking has Vision angles only (landmarks are gate-test-only), so the profile always uses them. A
    /// failed fit leaves the library unchanged and explains the problem in `calibrationMessage`.
    func refitCalibration(from trace: PoseTrace) {
        switch fitAndSave(trace) {
        case .success(let profile):
            calibrationMessage = nil
            lastFittedProfile = profile
        case .failure(let failure):
            calibrationMessage = .error(failure.text)
        }
    }

    /// Fits a Vision-angles profile from `trace` and saves it in the library. A failed fit saves nothing.
    func fitAndSave(_ trace: PoseTrace) -> Result<CalibrationProfile, FitFailure> {
        let result = fit(trace)
        if case .success(let profile) = result { saveToLibrary(profile) }
        return result
    }

    /// Fits a Vision-angles profile from `trace` without saving it.
    func fit(_ trace: PoseTrace) -> Result<CalibrationProfile, FitFailure> {
        do {
            return .success(try engine.fitProfile(from: trace, features: .visionAngles, rounds: nil))
        } catch let error as CalibrationError {
            log.info("Calibration fit failed: \(String(describing: error), privacy: .public)")
            return .failure(FitFailure(text: error.userMessage))
        } catch {
            log.error("Calibration fit failed: \(String(describing: error), privacy: .public)")
            return .failure(FitFailure(text: error.localizedDescription))
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
        syncCameraFallback()
    }

    /// Removes the calibration saved under `key` (M5's Settings list).
    func removeFromLibrary(_ key: CalibrationKey) {
        var updated = library
        updated.remove(key)
        guard updated != library else { return }
        library = updated
        persistLibrary()
        refreshActiveCalibration()
        syncCameraFallback()
    }

    // MARK: Resolution

    /// The name of the camera the calibration is looked up for: the running camera, else the one the session is waiting
    /// for or has been moved to (SPEC D46), else the one capture would pick (CONTRACT 6.1, asked of the camera service
    /// so the two never disagree).
    ///
    /// While the chosen camera is unplugged, capture's own rule would name the built-in camera. The session still
    /// belongs to the chosen camera though, and dropping its calibration would stop the camera we are waiting for.
    var trackingCameraName: String? {
        if let name = status.device?.name { return name }
        // Also while the source restarts for it: no stream then, but the stand-in is still the camera in use.
        if let fallbackCamera { return fallbackCamera.name }
        if let lost = unpluggedChosenCamera { return lost.name }
        return predictedCameraName
    }

    /// Re-asks the camera service which device capture would open, assigning only on a change.
    func refreshPredictedCamera() {
        let name = camera.resolvedDevice(for: selectedCameraID)?.name
        if name != predictedCameraName { predictedCameraName = name }
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
