import GanderUI
import SwiftUI

/// Entry point. Kept thin: all scenes live in `GanderUI`, all wiring in `AppComposition`.
@main
struct GanderApp: App {
    @State private var model = AppComposition.makeModel()

    var body: some Scene {
        GanderScenes(model: model)
    }
}
