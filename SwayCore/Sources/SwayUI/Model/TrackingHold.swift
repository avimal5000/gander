/// Why automatic switching is held right now (SPEC D28). The decider is told it is locked while any applies.
enum TrackingHold: Equatable {
    /// The user turned Focus Lock on.
    case focusLock
    /// Sway is the active app: its menu or a window is in front.
    case swayInFront
    /// A Focus Test countdown or request is running.
    case focusTest
    /// Sway's own focus request is in flight.
    case switching

    /// The wording in the Pose Debug window.
    var text: String {
        switch self {
        case .focusLock: "Focus Lock on"
        case .swayInFront: "Sway is in front"
        case .focusTest: "Focus Test running"
        case .switching: "Switching\u{2026}"
        }
    }
}
