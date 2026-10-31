import CoreGraphics
import Foundation
import GanderModels

@testable import FocusControl

/// Test builders for window-list entries, records, displays, and layouts.
enum FocusFixtures {
    /// A window-list entry shaped like the window server's, with every key present unless overridden to `nil`.
    static func entry(
        number: Int? = 1,
        processID: Int? = 100,
        ownerName: String? = "Safari",
        layer: Int? = 0,
        bounds: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
        alpha: Double? = 1
    ) -> [String: Any] {
        var entry: [String: Any] = [:]
        if let number { entry[kCGWindowNumber as String] = number }
        if let processID { entry[kCGWindowOwnerPID as String] = processID }
        if let ownerName { entry[kCGWindowOwnerName as String] = ownerName }
        if let layer { entry[kCGWindowLayer as String] = layer }
        if let bounds { entry[kCGWindowBounds as String] = bounds.dictionaryRepresentation }
        if let alpha { entry[kCGWindowAlpha as String] = alpha }
        return entry
    }

    static func record(
        number: UInt32 = 1,
        processID: Int32 = 100,
        ownerName: String = "Safari",
        layer: Int = 0,
        bounds: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
        alpha: Double = 1
    ) -> WindowRecord {
        WindowRecord(
            number: number,
            processID: processID,
            ownerName: ownerName,
            layer: layer,
            bounds: bounds,
            alpha: alpha
        )
    }

    /// A display with an AppKit (bottom-left origin) frame.
    static func display(
        _ id: String,
        appKitFrame: CGRect,
        isMain: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(
            id: DisplayID(id),
            cgDisplayID: 1,
            name: id,
            frame: appKitFrame,
            isBuiltIn: false,
            isMain: isMain
        )
    }

    /// Quartz frames given directly, bypassing AppKit conversion.
    static func quartz(_ id: String, _ frame: CGRect) -> QuartzDisplayFrame {
        QuartzDisplayFrame(id: DisplayID(id), frame: frame)
    }
}
