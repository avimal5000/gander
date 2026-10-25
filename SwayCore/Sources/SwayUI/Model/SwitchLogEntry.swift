import Foundation

/// One real switch in the Switch preview log (SPEC F11, F16). The text names the app and display, never a window
/// title.
struct SwitchLogEntry: Identifiable, Equatable {
    let id: Int
    /// Wall-clock time the result arrived.
    let time: Date
    let text: String
}
