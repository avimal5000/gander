/// The single banner the popover can show above the switches (SPEC F19). Pure, so the order is unit tested.
enum MenuBanner: Equatable {
    /// The camera permission explanation or instructions (SPEC F2); the permission view draws it.
    case cameraPermission
    /// Nothing is calibrated yet and the walkthrough was never finished.
    case firstSetup
    /// Two or more displays are connected and no saved calibration fits, while Tracking is on or nothing is calibrated
    /// at all.
    case needsCalibration
    /// As `needsCalibration`, but these displays are calibrated for another camera (SPEC F23). Carries the camera's
    /// name.
    case needsCameraCalibration(String)
    /// Tracking is on and calibrated, but Accessibility is not granted.
    case needsAccessibility
    /// The Focus Lock shortcut could not be registered.
    case shortcut(String)

    /// The window the banner's button opens, for the banners whose button opens one. Setting up, and calibrating for new
    /// displays or another camera, all go through the Setup window.
    var buttonWindowID: String? {
        switch self {
        case .firstSetup, .needsCalibration, .needsCameraCalibration: GanderWindowID.setup
        case .cameraPermission, .needsAccessibility, .shortcut: nil
        }
    }

    static let firstSetupText = "Gander needs a quick setup, about a minute."
    static let needsCalibrationText = "New display setup. Calibrate so Gander can switch between them."
    /// The button of both needs-calibration banners.
    static let calibrateButtonTitle = "Calibrate (about 20 s)\u{2026}"

    /// "No calibration for <camera> yet."
    static func needsCameraCalibrationText(camera: String) -> String {
        "No calibration for \(camera) yet."
    }

    static let needsAccessibilityText =
        "Gander needs Accessibility access to move keyboard focus to a window on the display you look at. "
        + "It never moves the cursor and never reads window contents."

    /// What the popover facts say to show, in priority order: at most one banner.
    struct Facts: Equatable {
        var hasPermissionPrompt: Bool
        var libraryIsEmpty: Bool
        var trackingEnabled: Bool
        var displayCount: Int
        var hasCalibration: Bool
        var accessibilityTrusted: Bool
        var shortcutMessage: String?
        /// The camera in use when it has no calibration for these displays but another camera does.
        var cameraWithoutCalibration: String?
        /// The walkthrough reached the camera check once, so the first setup is not offered again.
        var setupCompleted = false
    }

    static func current(_ facts: Facts) -> MenuBanner? {
        if facts.hasPermissionPrompt { return .cameraPermission }
        if facts.libraryIsEmpty, !facts.setupCompleted { return .firstSetup }
        // After the walkthrough with nothing calibrated, a second display is the moment to ask, Tracking on or not.
        if facts.trackingEnabled || facts.libraryIsEmpty, facts.displayCount >= 2, !facts.hasCalibration {
            return facts.cameraWithoutCalibration.map { .needsCameraCalibration($0) } ?? .needsCalibration
        }
        if facts.trackingEnabled, facts.hasCalibration, !facts.accessibilityTrusted { return .needsAccessibility }
        if let message = facts.shortcutMessage { return .shortcut(message) }
        return nil
    }
}
