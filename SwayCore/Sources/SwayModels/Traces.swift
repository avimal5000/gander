import Foundation

/// A contiguous run of samples, optionally labeled with the display the user was asked to look at.
public struct TraceSegment: Sendable, Equatable, Codable {
    /// Display the user was looking at; `nil` for unlabeled free recording.
    public var displayID: DisplayID?
    /// 1-based round within a gate test; 0 for free recordings.
    public var round: Int
    /// Samples in time order, including frames with no face.
    public var samples: [PoseSample]

    public init(displayID: DisplayID?, round: Int, samples: [PoseSample]) {
        self.displayID = displayID
        self.round = round
        self.samples = samples
    }
}

/// A recorded pose trace. Numeric only: no images, ever.
public struct PoseTrace: Sendable, Equatable, Codable, Identifiable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: UUID
    public var createdAt: Date
    /// Name of the camera used, if any.
    public var cameraName: String?
    /// Display layout at recording time.
    public var layout: DisplayLayout?
    public var segments: [TraceSegment]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        cameraName: String? = nil,
        layout: DisplayLayout? = nil,
        segments: [TraceSegment] = [],
        notes: String? = nil
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.createdAt = createdAt
        self.cameraName = cameraName
        self.layout = layout
        self.segments = segments
        self.notes = notes
    }
}

public enum TraceStoreError: Error, Sendable, Equatable {
    /// Traces are only written in DEBUG builds (PLAN.md privacy guarantee).
    case disabledInReleaseBuilds
    case io(String)
    case decoding(String)
}

/// Persists pose traces as JSON. Implemented by `PoseTraces.FileTraceStore`.
public protocol TraceStoring: Sendable {
    /// Folder holding traces. Default: `~/Library/Application Support/Sway/Traces`.
    var directory: URL { get }
    /// Writes pretty-printed JSON named `<yyyyMMdd-HHmmss>-<first 8 of id>.json` and returns its URL.
    /// In non-DEBUG builds it writes nothing and throws `.disabledInReleaseBuilds`.
    func save(_ trace: PoseTrace) throws -> URL
    /// Reads a trace (works in every build configuration).
    func load(_ url: URL) throws -> PoseTrace
    /// Trace files in `directory`, newest first. Empty if the folder does not exist.
    func list() throws -> [URL]
}
