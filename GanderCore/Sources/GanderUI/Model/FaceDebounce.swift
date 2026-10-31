import Foundation

/// Steadies the "No face" status (CONTRACT 6.5.5): a face shows at once, but "no face" only after the face has been
/// missing for ``absentDelay``. A one-frame miss, a blink of the detector, or a head turn through the edge of the
/// camera's view then never flashes the status.
///
/// Pure and clock-free: it works on the samples' own timestamps, so a source that slows down (the adaptive frame rate
/// after 2 s without a face) loses nothing, because the frames that matter come well inside the delay.
struct FaceDebounce: Equatable, Sendable {
    /// How long a face must be missing before ``isPresent`` turns false, in seconds.
    static let absentDelay: TimeInterval = 0.5

    /// What the status should treat as "a face is there".
    private(set) var isPresent = false
    /// The timestamp of the latest sample that had a face.
    private var lastSeen: TimeInterval?

    init() {}

    /// Feeds one sample and returns ``isPresent``.
    @discardableResult
    mutating func update(face: Bool, at timestamp: TimeInterval) -> Bool {
        if face {
            lastSeen = timestamp
            isPresent = true
        } else if isPresent, let seen = lastSeen {
            // A clock that restarted lower must not pin the status to "face" until it catches up.
            let reference = min(seen, timestamp)
            lastSeen = reference
            if timestamp - reference >= Self.absentDelay { isPresent = false }
        }
        return isPresent
    }

    /// Forgets everything: the camera stopped, restarted, or was interrupted.
    mutating func reset() {
        self = FaceDebounce()
    }
}
