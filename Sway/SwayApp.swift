import SwayUI
import SwiftUI

/// Entry point. Kept thin: all scenes live in `SwayUI`, all wiring in `AppComposition`.
@main
struct SwayApp: App {
    @State private var model = AppComposition.makeModel()

    var body: some Scene {
        SwayScenes(model: model)
    }
}
