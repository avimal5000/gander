import Foundation
import SwayModels

/// One saved calibration in the Settings list.
struct CalibrationRow: Identifiable, Equatable {
    let key: CalibrationKey
    /// The displays by name, in the order they were calibrated: "Left, Right".
    let displays: String
    let camera: String
    let date: Date
    /// This is the calibration tracking uses now.
    let isInUse: Bool

    var id: CalibrationKey { key }
}

/// Builds the Settings window's calibration list. Pure.
enum CalibrationListPresentation {
    /// Shown for a calibration whose trace had no camera name.
    static let unknownCamera = "Unknown camera"

    /// One row per saved profile, in library order (newest first). `activeKey` is the calibration in use, and
    /// `name` labels a display.
    static func rows(
        library: CalibrationLibrary, activeKey: CalibrationKey?, name: (DisplayID) -> String
    ) -> [CalibrationRow] {
        library.profiles.map { profile in
            CalibrationRow(
                key: profile.key,
                displays: profile.displays.map { name($0.displayID) }.joined(separator: ", "),
                camera: profile.cameraName ?? unknownCamera,
                date: profile.createdAt,
                isInUse: profile.key == activeKey
            )
        }
    }
}
