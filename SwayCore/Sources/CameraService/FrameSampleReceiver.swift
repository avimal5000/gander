import AVFoundation
import CoreMedia
import SwayModels
import os

/// Receives sample buffers on the frame queue and hands them to the frame handler as `CameraFrame`s.
///
/// Only the pixel buffer reference and the presentation time are read. Nothing is copied or stored, and the
/// frame is dropped when the handler returns. After `disable()` no further frame reaches the handler.
final class FrameSampleReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    // Sendable by construction: every stored property is an immutable `let` of a Sendable type; the mutable
    // state lives inside the unfair locks.
    private let handler: OSAllocatedUnfairLock<(@Sendable (CameraFrame) -> Void)?>
    private let watchdog: OSAllocatedUnfairLock<FrameWatchdog>
    private let onFramesResumed: @Sendable () -> Void

    /// - Parameters:
    ///   - frameHandler: called for every frame, on the frame queue.
    ///   - watchdog: shared with the controller; updated for every frame.
    ///   - onFramesResumed: called on the frame queue when the watchdog reports `.resumed`.
    init(
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        watchdog: OSAllocatedUnfairLock<FrameWatchdog>,
        onFramesResumed: @escaping @Sendable () -> Void
    ) {
        self.handler = OSAllocatedUnfairLock(initialState: frameHandler)
        self.watchdog = watchdog
        self.onFramesResumed = onFramesResumed
        super.init()
    }

    /// Stops delivery. A frame already inside the handler finishes; the controller drains the frame queue
    /// afterwards so that no handler call is in flight once teardown returns.
    func disable() {
        handler.withLock { $0 = nil }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let handler = handler.withLock({ $0 }) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let uptime = ProcessInfo.processInfo.systemUptime
        if watchdog.withLock({ $0.frameReceived(at: uptime) }) != nil {
            onFramesResumed()
        }

        let presentationSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let timestamp = presentationSeconds.isFinite ? presentationSeconds : uptime
        handler(CameraFrame(pixelBuffer: pixelBuffer, timestamp: timestamp))
    }
}
