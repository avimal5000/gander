import AVFoundation
import CoreMedia
import SwayModels
import os

/// Receives sample buffers on the frame queue and hands them to the frame handler as `CameraFrame`s.
///
/// Only the pixel buffer reference and the presentation time are read. Nothing is copied or stored, and the
/// frame is dropped when the handler returns. After `disable()` no further frame reaches the handler.
final class FrameSampleReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    /// The frame handler, wrapped in a struct before it goes into the lock.
    ///
    /// A bare function type stored in a generic container is re-abstracted on every `withLock` call: each access
    /// wraps the stored closure in two more thunks. At camera frame rate the chain was thousands deep within a
    /// couple of minutes, every frame called through all of it, and releasing it in `disable()` overflowed the
    /// session queue's stack (the crash on turning Live off). A struct field has one fixed representation, so
    /// nothing is wrapped.
    private struct Delivery: Sendable {
        var handler: (@Sendable (CameraFrame) -> Void)?
    }

    // Sendable by construction: every stored property is an immutable `let` of a Sendable type; the mutable
    // state lives inside the unfair locks.
    private let delivery: OSAllocatedUnfairLock<Delivery>
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
        self.delivery = OSAllocatedUnfairLock(initialState: Delivery(handler: frameHandler))
        self.watchdog = watchdog
        self.onFramesResumed = onFramesResumed
        super.init()
    }

    /// Stops delivery and releases the handler. A frame already inside the handler finishes; the controller
    /// drains the frame queue afterwards so that no handler call is in flight once teardown returns.
    func disable() {
        delivery.withLock { $0.handler = nil }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        deliver(pixelBuffer, presentationSeconds: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }

    /// One frame: updates the watchdog and calls the handler, unless disabled. Split from `captureOutput` so
    /// tests can deliver frames without a capture connection.
    func deliver(_ pixelBuffer: CVPixelBuffer, presentationSeconds: Double) {
        guard let handler = delivery.withLock({ $0 }).handler else { return }

        let uptime = ProcessInfo.processInfo.systemUptime
        if watchdog.withLock({ $0.frameReceived(at: uptime) }) != nil {
            onFramesResumed()
        }

        let timestamp = presentationSeconds.isFinite ? presentationSeconds : uptime
        handler(CameraFrame(pixelBuffer: pixelBuffer, timestamp: timestamp))
    }
}
