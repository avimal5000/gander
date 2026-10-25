import SwayModels

/// The menu popover's one-line live readout. Pure, so it is unit tested.
///
/// Every case is one line of the same height, so the popover never changes size when the camera starts or stops
/// (it used to drop the line when the camera turned off, resizing the popover under the toggle that was just clicked).
enum MenuReadout: Equatable {
    case angles(yaw: String, pitch: String)
    case noFace

    /// Dashes: the camera is off, or the popover is closed and draws nothing live.
    static let placeholder = MenuReadout.angles(yaw: Formatting.missing, pitch: Formatting.missing)

    static func make(pose: HeadPose?, isRunning: Bool) -> MenuReadout {
        if let pose {
            return .angles(yaw: Formatting.degrees(pose.yaw), pitch: Formatting.degrees(pose.pitch))
        }
        return isRunning ? .noFace : placeholder
    }
}
