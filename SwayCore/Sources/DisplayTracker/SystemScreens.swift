import AppKit
import CoreGraphics
import Foundation
import SwayModels
import os

/// Reads the real screens from AppKit and CoreGraphics. The only place in the module that touches `NSScreen`.
@MainActor
enum SystemScreens {
    private static let logger = SwayLog.logger(category: "displays")
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    /// A descriptor for every screen in `NSScreen.screens`, in AppKit's order.
    static func current() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap { descriptor(for: $0) }
    }

    /// The descriptor for one screen, or `nil` when AppKit gives it no display number (it cannot be identified).
    static func descriptor(for screen: NSScreen) -> ScreenDescriptor? {
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            logger.warning("Skipping a screen with no NSScreenNumber")
            return nil
        }
        let displayID = number.uint32Value
        return ScreenDescriptor(
            cgDisplayID: displayID,
            uuidString: uuidString(for: displayID),
            name: screen.localizedName,
            frame: screen.frame,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
            isMain: CGDisplayIsMain(displayID) != 0
        )
    }

    /// The string form of the display's UUID, or `nil` when CoreGraphics returns none.
    nonisolated static func uuidString(for displayID: UInt32) -> String? {
        // The "Create" function returns a +1 reference that is not annotated, so Swift imports it unmanaged.
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
