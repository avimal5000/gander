/// The rows that open a window. The popover lists only `menu` (then Quit Gander); the tools for checking Gander, and
/// the Welcome Tour, sit in the Advanced section of Settings (`advanced`), so the menu stays short (SPEC F19).
enum MenuWindowItem: CaseIterable, Equatable {
    case calibrate
    case settings
    case poseDebug
    case gateTest
    case focusTest
    case welcomeTour

    /// The rows of the menu bar popover.
    static let menu: [MenuWindowItem] = [.calibrate, .settings]

    /// The rows of Settings > Advanced.
    static let advanced: [MenuWindowItem] = [.welcomeTour, .poseDebug, .gateTest, .focusTest]

    var title: String {
        switch self {
        case .calibrate: "Calibrate\u{2026}"
        case .settings: "Settings\u{2026}"
        case .poseDebug: "Pose Debug Window\u{2026}"
        case .gateTest: "Head-Pose Gate Test\u{2026}"
        case .focusTest: "Focus Test Window\u{2026}"
        case .welcomeTour: "Welcome Tour\u{2026}"
        }
    }

    /// One line under the row in Settings > Advanced.
    var help: String {
        switch self {
        case .calibrate: "Look at each display once so Gander learns where they are."
        case .settings: "Appearance, switching, the shortcut and calibrations."
        case .poseDebug: "Shows the head angles Gander measures, live, and can record them."
        case .gateTest: "Checks that Gander can tell your displays apart by where you look."
        case .focusTest: "Checks that Gander can move keyboard focus between your displays."
        case .welcomeTour: "Replays the short introduction to Gander."
        }
    }

    /// The SF Symbol beside the title.
    var systemImage: String {
        switch self {
        case .calibrate: "viewfinder"
        case .settings: "gearshape"
        case .poseDebug: "waveform.path.ecg"
        case .gateTest: "scope"
        case .focusTest: "rectangle.2.swap"
        case .welcomeTour: "sparkles"
        }
    }

    /// The window the row opens.
    var windowID: String {
        switch self {
        case .calibrate: GanderWindowID.setup
        case .settings: GanderWindowID.settings
        case .poseDebug: GanderWindowID.poseDebug
        case .gateTest: GanderWindowID.gateTest
        case .focusTest: GanderWindowID.focusTest
        case .welcomeTour: GanderWindowID.setup
        }
    }
}
