import Foundation

/// What the log says about a display or Space hold (CONTRACT 6.5.5 item 1): which hold, how long it lasted, and what
/// ended it. Pure, so the wording is tested. Never carries a window title.
enum HoldLog {
    /// Which hold.
    enum Kind: String, Equatable {
        case displays = "Display"
        case space = "Space"
    }

    /// What ended a hold.
    enum End: String, Equatable {
        /// The new layout reached `layoutDidChange`.
        case layout
        /// The wait for a layout ran out.
        case timeout
        /// A display hold reached its cap: notifications kept coming without a layout.
        case cap
    }

    static func started(_ kind: Kind) -> String {
        "\(kind.rawValue) hold started"
    }

    static func ended(_ kind: Kind, by end: End, after seconds: TimeInterval) -> String {
        "\(kind.rawValue) hold ended by \(end.rawValue) after \(Formatting.twoDecimals(max(0, seconds))) s"
    }
}
