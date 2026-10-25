import AppKit
import SwayModels

/// Finds the `NSScreen` that shows a given display (CONTRACT 6.5).
enum ScreenMatcher {
    /// Key under which AppKit stores the `CGDirectDisplayID` in a screen's device description.
    static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    /// True when a device description (as found on `NSScreen.deviceDescription`) describes `cgDisplayID`.
    static func matches(deviceDescription: [NSDeviceDescriptionKey: Any], cgDisplayID: UInt32) -> Bool {
        guard let number = deviceDescription[screenNumberKey] as? NSNumber else { return false }
        return number.uint32Value == cgDisplayID
    }

    /// The first of `screens` showing `display`; `nil` if it is not connected.
    @MainActor
    static func screen(for display: DisplayInfo, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { matches(deviceDescription: $0.deviceDescription, cgDisplayID: display.cgDisplayID) }
    }
}
