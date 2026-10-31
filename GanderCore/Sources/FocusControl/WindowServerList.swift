import CoreGraphics
import Foundation

/// Reads the window server's on-screen window list. Needs no permission for owner, layer, and bounds.
enum WindowServerList {
    /// All on-screen windows, front to back, without desktop elements. Empty if the list is unavailable.
    static func currentRecords() -> [WindowRecord] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return WindowRecord.parse(entries)
    }
}
