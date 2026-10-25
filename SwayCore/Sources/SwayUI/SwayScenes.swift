import SwiftUI

/// Every scene of the app; the app target's `body` is just `SwayScenes(model:)`.
///
/// - The menu bar item (window style) with the status, live toggle, and shortcuts.
/// - "Pose Debug": live pose numbers, a 10 s plot, the live guess, and the Switch preview.
/// - "Head-Pose Gate Test": the guided test and its report.
/// - "Focus Test": Accessibility onboarding and manual focus requests per display.
public struct SwayScenes: Scene {
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

        Window("Pose Debug", id: SwayWindowID.poseDebug) {
            PoseDebugView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Head-Pose Gate Test", id: SwayWindowID.gateTest) {
            GateTestView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Focus Test", id: SwayWindowID.focusTest) {
            FocusTestView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
