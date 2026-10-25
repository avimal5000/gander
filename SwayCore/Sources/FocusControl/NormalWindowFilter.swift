import Foundation

/// Decides which window-list entries are ordinary application windows worth focusing.
enum NormalWindowFilter {
    /// Owners whose windows are system furniture, never a window the user works in.
    static let excludedOwnerNames: Set<String> = ["Window Server", "Dock", "WindowManager"]
    /// Windows with `alpha` at or below this are invisible.
    static let minimumAlpha = 0.01
    /// Smaller windows are palettes, badges, or helpers.
    static let minimumWidth: CGFloat = 120
    static let minimumHeight: CGFloat = 80

    /// True when `record` is an ordinary, visible, reasonably sized window of another app.
    static func isNormal(_ record: WindowRecord, ownProcessID: Int32) -> Bool {
        record.layer == 0
            && record.alpha > minimumAlpha
            && record.bounds.width >= minimumWidth
            && record.bounds.height >= minimumHeight
            && record.processID != ownProcessID
            && !excludedOwnerNames.contains(record.ownerName)
    }
}
