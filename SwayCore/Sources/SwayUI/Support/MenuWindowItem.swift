/// The menu rows that open a window, in the order the popover lists them (SPEC F19). Quit Gander follows them.
enum MenuWindowItem: CaseIterable, Equatable {
    case calibrate
    case settings
    case poseDebug
    case gateTest
    case focusTest

    var title: String {
        switch self {
        case .calibrate: "Calibrate\u{2026}"
        case .settings: "Settings\u{2026}"
        case .poseDebug: "Pose Debug Window\u{2026}"
        case .gateTest: "Head-Pose Gate Test\u{2026}"
        case .focusTest: "Focus Test Window\u{2026}"
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
        }
    }

    /// The window the row opens.
    var windowID: String {
        switch self {
        case .calibrate: SwayWindowID.setup
        case .settings: SwayWindowID.settings
        case .poseDebug: SwayWindowID.poseDebug
        case .gateTest: SwayWindowID.gateTest
        case .focusTest: SwayWindowID.focusTest
        }
    }
}
