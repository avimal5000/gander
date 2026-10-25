import Foundation

/// One would-be switch in the Switch preview log (SPEC F11). Display names only: nothing about windows.
struct SwitchLogEntry: Identifiable, Equatable {
    let id: Int
    /// Wall-clock time of the switch.
    let time: Date
    /// Label of the display the decider would have switched to.
    let displayName: String
    /// Seconds from the first sample of the dwell to the sample that completed it.
    let latency: TimeInterval
}
