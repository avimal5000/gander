import CoreGraphics
import Foundation

/// Stable display identity: the string form of `CGDisplayCreateUUIDFromDisplayID`.
/// Survives reboots and reconnects for the same physical monitor.
public struct DisplayID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

/// One connected display.
public struct DisplayInfo: Sendable, Equatable, Codable, Identifiable {
    public let id: DisplayID
    /// `CGDirectDisplayID`. Valid for the current login session only; never persist as identity.
    public let cgDisplayID: UInt32
    /// `NSScreen.localizedName`.
    public let name: String
    /// Global AppKit coordinates in points (origin at the bottom-left of the main display).
    public let frame: CGRect
    /// `CGDisplayIsBuiltin`.
    public let isBuiltIn: Bool
    /// `CGDisplayIsMain` (the display with the menu bar).
    public let isMain: Bool

    public init(id: DisplayID, cgDisplayID: UInt32, name: String, frame: CGRect, isBuiltIn: Bool, isMain: Bool) {
        self.id = id
        self.cgDisplayID = cgDisplayID
        self.name = name
        self.frame = frame
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
    }
}

/// The current arrangement of displays.
public struct DisplayLayout: Sendable, Equatable, Codable {
    /// Sorted left to right by `frame.minX`, then `frame.minY`, then ID.
    public let displays: [DisplayInfo]
    /// Canonical identity of this arrangement, built from display IDs and frames (not `cgDisplayID`).
    /// The same physical arrangement always yields the same fingerprint.
    public let fingerprint: String

    public init(displays: [DisplayInfo]) {
        let sorted = displays.sorted {
            ($0.frame.minX, $0.frame.minY, $0.id.rawValue) < ($1.frame.minX, $1.frame.minY, $1.id.rawValue)
        }
        self.displays = sorted
        self.fingerprint = sorted.map { display in
            let frame = display.frame.integral
            return
                "\(display.id.rawValue)@\(Int(clamping: frame.minX)),\(Int(clamping: frame.minY)),"
                + "\(Int(clamping: frame.width))x\(Int(clamping: frame.height))"
        }
        .joined(separator: "|")
    }

    public static let empty = DisplayLayout(displays: [])

    public func display(withID id: DisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }
}

/// Reports the display layout and its changes. Implemented by `DisplayTracker.ScreenDisplayTracker`.
@MainActor
public protocol DisplayProviding: AnyObject {
    /// The layout right now.
    var currentLayout: DisplayLayout { get }
    /// A new independent stream that yields the current layout immediately, then each distinct
    /// change (debounced about 0.5 s, consecutive duplicates dropped).
    func layouts() -> AsyncStream<DisplayLayout>
}
