import GanderModels

/// One synthetic pose cluster: a display the simulated user looks at, and the head pose that implies.
public struct SyntheticCluster: Sendable, Equatable {
    /// The display this cluster is labeled with.
    public var displayID: DisplayID
    /// Cluster center yaw, degrees.
    public var yaw: Double
    /// Cluster center pitch, degrees.
    public var pitch: Double

    /// Creates a cluster centered at (`yaw`, `pitch`) for `displayID`.
    public init(displayID: DisplayID, yaw: Double, pitch: Double) {
        self.displayID = displayID
        self.yaw = yaw
        self.pitch = pitch
    }
}
