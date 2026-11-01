import GanderModels

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
            shortcutMessage: menuShortcutMessage,
            cameraWithoutCalibration: cameraWithoutCalibration,
            setupCompleted: setupCompleted
        )
    }

    /// The camera in use when these displays are calibrated for another camera but not for this one (SPEC F23); `nil`
    /// otherwise. Read only while nothing fits, so the popover does not follow the library at other times.
    var cameraWithoutCalibration: String? {
        guard activeCalibration == nil, layout.displays.count >= 2, let camera = trackingCameraName else { return nil }
        let connected = Set(layout.displays.map(\.id))
        let calibratedForAnotherCamera = library.profiles.contains {
            $0.cameraName != camera && connected.isSubset(of: $0.displayIDs)
        }
        return calibratedForAnotherCamera ? camera : nil
    }

    /// The single banner to show above the switches, if any.
    var menuBanner: MenuBanner? { MenuBanner.current(menuBannerFacts) }
}
