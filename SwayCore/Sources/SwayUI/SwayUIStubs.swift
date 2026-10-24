import AppKit
import Observation
import SwayModels
import SwiftUI

// SKELETON STUB (orchestrator). The SwayUI builder replaces this file. See CONTRACT.md.

/// Root observable state and coordinator for the M1 app.
@MainActor
@Observable
public final class AppModel {
    private let camera: any FrameSource
    private let poseSource: any PoseSource
    private let displays: any DisplayProviding
    private let traceStore: any TraceStoring
    private let analyzer: any SeparabilityAnalyzing
    private let defaults: UserDefaults

    public init(
        camera: any FrameSource,
        poseSource: any PoseSource,
        displays: any DisplayProviding,
        traceStore: any TraceStoring,
        analyzer: any SeparabilityAnalyzing,
        defaults: UserDefaults = .standard
    ) {
        self.camera = camera
        self.poseSource = poseSource
        self.displays = displays
        self.traceStore = traceStore
        self.analyzer = analyzer
        self.defaults = defaults
    }
}

/// Every scene of the app; the app target's `body` is just `SwayScenes(model:)`.
public struct SwayScenes: Scene {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Scene {
        MenuBarExtra("Sway", systemImage: "eye") {
            Text("Sway skeleton")
            Button("Quit Sway") { NSApplication.shared.terminate(nil) }
        }
    }
}
