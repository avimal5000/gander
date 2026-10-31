import Foundation
import GanderModels

/// Picks each display's last-used window from a z-ordered window list.
enum LastUsedWindowSelector {
    /// For each display, the first (frontmost) normal window assigned to it. `records` must be ordered front
    /// to back. Windows of `ownProcessID` and windows that overlap no display are ignored, and displays
    /// without a window are absent from the result.
    static func select(
        from records: [WindowRecord],
        displays: [QuartzDisplayFrame],
        ownProcessID: Int32
    ) -> [DisplayID: WindowRecord] {
        var selected: [DisplayID: WindowRecord] = [:]
        for record in records {
            if selected.count == displays.count { break }
            guard NormalWindowFilter.isNormal(record, ownProcessID: ownProcessID),
                let displayID = DisplayGeometry.assignedDisplay(for: record.bounds, in: displays),
                selected[displayID] == nil
            else {
                continue
            }
            selected[displayID] = record
        }
        return selected
    }

    /// The frontmost normal window of `processID`, with the display it is on. `nil` if it has none on a display.
    static func frontmostWindow(
        ofProcess processID: Int32,
        in records: [WindowRecord],
        displays: [QuartzDisplayFrame],
        ownProcessID: Int32
    ) -> (record: WindowRecord, displayID: DisplayID)? {
        for record in records where record.processID == processID {
            guard NormalWindowFilter.isNormal(record, ownProcessID: ownProcessID),
                let displayID = DisplayGeometry.assignedDisplay(for: record.bounds, in: displays)
            else {
                continue
            }
            return (record, displayID)
        }
        return nil
    }
}
