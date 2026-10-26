/// Why automatic switching is held right now (SPEC D28, D44). The decider is told it is locked while any applies.
enum TrackingHold: Equatable {
    /// The user turned Focus Lock on.
    case focusLock
    /// Sway is the active app: its menu or a window is in front.
    case swayInFront
    /// A Focus Test countdown or request is running.
    case focusTest
    /// The displays are being plugged, unplugged, or rearranged and the new layout is not known yet. Not shown in the
    /// menu.
    case displaysChanging
    /// A Space just changed, so the window server's idea of the front window is still settling. Not shown in the menu.
    case spaceChanging
    /// Sway's own focus request is in flight.
    case switching

    /// The wording in the Pose Debug window.
    var text: String {
        switch self {
        case .focusLock: "Focus Lock on"
        case .swayInFront: "Sway is in front"
        case .focusTest: "Focus Test running"
        case .displaysChanging: "Displays changing\u{2026}"
        case .spaceChanging: "Space changing\u{2026}"
        case .switching: "Switching\u{2026}"
        }
    }
}
