/// The single banner the popover can show above the switches (SPEC F19). Pure, so the order is unit tested.
enum MenuBanner: Equatable {
    /// The camera permission explanation or instructions (SPEC F2); the permission view draws it.
    case cameraPermission
    /// Nothing is calibrated yet.
    case firstSetup
    /// Tracking is on, two or more displays are connected, and no saved calibration fits.
    case needsCalibration
    /// Tracking is on and calibrated, but Accessibility is not granted.
    case needsAccessibility
    /// The Focus Lock shortcut could not be registered.
    case shortcut(String)

    static let firstSetupText = "Sway needs a quick setup, about a minute."
    static let needsCalibrationText = "New display setup. Calibrate so Sway can switch between them."
    static let needsAccessibilityText =
        "Sway needs Accessibility access to move keyboard focus to a window on the display you look at. "
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
    }

    static func current(_ facts: Facts) -> MenuBanner? {
        if facts.hasPermissionPrompt { return .cameraPermission }
        if facts.libraryIsEmpty { return .firstSetup }
        if facts.trackingEnabled, facts.displayCount >= 2, !facts.hasCalibration { return .needsCalibration }
        if facts.trackingEnabled, facts.hasCalibration, !facts.accessibilityTrusted { return .needsAccessibility }
        if let message = facts.shortcutMessage { return .shortcut(message) }
        return nil
    }
}
