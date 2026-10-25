import SwayModels

// What the menu popover needs beyond the status: the one banner it may show.
extension AppModel {
    /// The facts the banner choice depends on (all assigned on change, never at the frame rate).
    var menuBannerFacts: MenuBanner.Facts {
        MenuBanner.Facts(
            hasPermissionPrompt: permissionPrompt != nil,
            libraryIsEmpty: library.profiles.isEmpty,
            trackingEnabled: trackingEnabled,
            displayCount: layout.displays.count,
            hasCalibration: activeCalibration != nil,
            accessibilityTrusted: isAccessibilityTrusted,
            shortcutMessage: shortcutMessage
        )
    }

    /// The single banner to show above the switches, if any.
    var menuBanner: MenuBanner? { MenuBanner.current(menuBannerFacts) }
}
