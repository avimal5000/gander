import SwiftUI

/// Every scene of the app; the app target's `body` is just `GanderScenes(model:)`.
///
/// - The menu bar item (window style) with the status, the Tracking and Focus Lock switches, and shortcuts.
/// - "Pose Debug": live pose numbers, a 10 s plot, the live guess, and the Switch preview of the real loop.
/// - "Head-Pose Gate Test": the guided test and its report.
/// - "Focus Test": Accessibility onboarding and manual focus requests per display.
/// - "Set Up Gander": permissions, a camera check, and the guided calibration.
/// - "Gander Settings": login item, switching sensitivity, Focus Lock shortcut, camera, and saved calibrations.
public struct GanderScenes: Scene {
    private let model: AppModel

    /// Creates the scenes for `model`.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Pose Debug", id: GanderWindowID.poseDebug) {
            PoseDebugView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Head-Pose Gate Test", id: GanderWindowID.gateTest) {
            GateTestView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Focus Test", id: GanderWindowID.focusTest) {
            FocusTestView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Set Up Gander", id: GanderWindowID.setup) {
            SetupView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Gander Settings", id: GanderWindowID.settings) {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
