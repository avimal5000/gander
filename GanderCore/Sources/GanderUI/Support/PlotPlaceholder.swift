import GanderModels

/// The text shown over the live plot when it has nothing to draw. Pure, so it is unit tested.
enum PlotPlaceholder {
    static let landmarksOnlyDuringGate = "Landmark angles are computed only during the gate test."
    static let waitingForFace = "Waiting for a face\u{2026}"
    static let cameraOff = "Turn the camera on to see live pose"

    /// - Parameters:
    ///   - hasFacePoints: the history holds at least one face pose (with any features).
    ///   - hasPlottedPoints: at least one of those has the plotted feature set's features.
    ///   - isRunning: the camera is delivering frames.
    /// - Returns: `nil` when there is something to plot.
    static func text(
        featureSet: PoseFeatureSet, hasFacePoints: Bool, hasPlottedPoints: Bool, isRunning: Bool
    )
        -> String?
    {
        if hasPlottedPoints { return nil }
        if hasFacePoints && featureSet == .landmarkAngles { return landmarksOnlyDuringGate }
        return isRunning ? waitingForFace : cameraOff
    }
}
