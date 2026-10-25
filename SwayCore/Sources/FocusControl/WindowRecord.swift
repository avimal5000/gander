import CoreGraphics
import Foundation

/// One entry of the window server's on-screen window list, reduced to the fields Sway needs.
struct WindowRecord: Equatable, Sendable {
    /// `kCGWindowNumber`.
    let number: UInt32
    /// `kCGWindowOwnerPID`.
    let processID: Int32
    /// `kCGWindowOwnerName`, or "" when the entry has none.
    let ownerName: String
    /// `kCGWindowLayer`. Layer 0 holds ordinary application windows.
    let layer: Int
    /// `kCGWindowBounds` in Quartz global coordinates (origin at the top-left of the main display).
    let bounds: CGRect
    /// `kCGWindowAlpha`, 1 when the entry has none.
    let alpha: Double
}

extension WindowRecord {
    /// Parses one window-list dictionary. Returns `nil` when the number, owner pid, or bounds is missing or
    /// malformed. A missing owner name becomes "", a missing alpha becomes 1, and a missing layer becomes 0
    /// (the layer of ordinary windows; the real window list always supplies it).
    init?(entry: [String: Any]) {
        guard
            let numberValue = Self.integer(entry[kCGWindowNumber as String]),
            let number = UInt32(exactly: numberValue),
            let pidValue = Self.integer(entry[kCGWindowOwnerPID as String]),
            let processID = Int32(exactly: pidValue),
            let boundsValue = entry[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsValue as CFDictionary)
        else {
            return nil
        }
        self.number = number
        self.processID = processID
        self.ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
        self.layer = Self.integer(entry[kCGWindowLayer as String]).flatMap { Int(exactly: $0) } ?? 0
        self.bounds = bounds
        self.alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    }

    /// Parses a window list, keeping the window server's front-to-back order and skipping unusable entries.
    static func parse(_ entries: [[String: Any]]) -> [WindowRecord] {
        entries.compactMap { WindowRecord(entry: $0) }
    }

    /// An integer from a number-like value, or `nil` for anything else.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        return number.int64Value
    }
}
