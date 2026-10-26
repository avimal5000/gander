import Foundation

/// Options for starting a `PoseSource`.
public struct PoseSourceConfiguration: Sendable, Equatable {
    /// Preferred camera; `nil` selects the default (built-in first). Ignored by non-camera sources.
    public var cameraDeviceID: String?
    /// Target frames per second.
    public var frameRate: Double
    /// Also compute the landmark-derived angles (`HeadPose.landmarkYaw` / `landmarkPitch`). This costs a second
    /// Vision request per frame, so only the gate test turns it on; live tracking uses Vision's angles alone.
    public var includeLandmarks: Bool

    public init(
        cameraDeviceID: String? = nil,
        frameRate: Double = SwayPolicy.defaultFrameRate,
        includeLandmarks: Bool = false
    ) {
        self.cameraDeviceID = cameraDeviceID
        self.frameRate = frameRate
        self.includeLandmarks = includeLandmarks
    }
}

/// An element of a pose source's event stream.
public enum PoseSourceEvent: Sendable, Equatable {
    case sample(PoseSample)
    case status(CaptureStatus)
}

/// How much frame rate the app needs from a live pose source right now (SPEC D45).
public enum PoseDemand: Sendable, Equatable {
    /// Every frame up to the 15 fps cap: calibration, the gate test, Setup's camera check, Pose Debug.
    case full
    /// Tracking: full rate while a face is present; a lower rate once no face has been seen for 2 s.
    case adaptive
    /// The camera must stay on, but nothing switches on the poses (Focus Lock, Accessibility needed): a low rate.
    case reduced
}

/// A stream of head poses: live camera, replayed trace, or synthetic data (tests).
public protocol PoseSource: AnyObject, Sendable {
    /// Starts the source and returns a fresh event stream.
    ///
    /// If the source is already running, the previous run is stopped and its stream finishes first.
    /// The stream emits `.status` events for every lifecycle change and `.sample` per processed frame.
    /// - Throws: `CameraError` for startup failures (for example `.notAuthorized`). Never prompts.
    func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent>
    /// Stops the source. The current stream emits `.status(.stopped)` and finishes. Idempotent.
    func stop() async
    /// Tells a live source how much frame rate is needed. Thread-safe and cheap; takes effect on the next frame and
    /// lasts until the next call. A source that does not throttle ignores it (the default).
    func setDemand(_ demand: PoseDemand)
}

extension PoseSource {
    public func setDemand(_ demand: PoseDemand) {}
}

/// Turns a camera frame into a head pose.
public protocol PoseEstimating: Sendable {
    /// Synchronously estimates the pose of the largest face in the frame; `nil` if none.
    /// Called on the capture queue, so it must finish well within one frame interval.
    /// - Parameter includeLandmarks: also fill `landmarkYaw` / `landmarkPitch`; when `false` they are `nil` and
    ///   no landmark request runs.
    func estimate(_ frame: CameraFrame, includeLandmarks: Bool) -> HeadPose?
}
