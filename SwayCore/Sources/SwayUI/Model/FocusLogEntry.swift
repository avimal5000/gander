import Foundation

/// One result in the Focus Test log. The text names the app and the display, never a window title.
struct FocusLogEntry: Identifiable, Equatable {
    let id: Int
    /// Wall-clock time the result arrived.
    let time: Date
    let text: String
}
