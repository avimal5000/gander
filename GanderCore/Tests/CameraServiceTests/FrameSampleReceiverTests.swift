import CoreVideo
import Foundation
import GanderModels
import Testing
import os

@testable import CameraService

@Suite("Frame sample receiver")
struct FrameSampleReceiverTests {
    private final class Token: Sendable {}

    /// A tiny in-memory buffer; the receiver only passes it through.
    private static func pixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            preconditionFailure("CVPixelBufferCreate failed with status \(status)")
        }
        return buffer
    }

    private func receiver(handler: @escaping @Sendable (CameraFrame) -> Void) -> FrameSampleReceiver {
        FrameSampleReceiver(
            frameHandler: handler,
            watchdog: OSAllocatedUnfairLock(initialState: FrameWatchdog()),
            onFramesResumed: {}
        )
    }

    @Test func framesReachTheHandlerUntilDisabled() {
        let timestamps = OSAllocatedUnfairLock(initialState: [Double]())
        let receiver = receiver { frame in timestamps.withLock { $0.append(frame.timestamp) } }
        let buffer = Self.pixelBuffer()

        receiver.deliver(buffer, presentationSeconds: 1)
        receiver.deliver(buffer, presentationSeconds: 2)
        receiver.disable()
        receiver.deliver(buffer, presentationSeconds: 3)

        #expect(timestamps.withLock { $0 } == [1, 2])
    }

    @Test func disableReleasesTheHandler() {
        weak var captured: Token?
        let receiver: FrameSampleReceiver
        do {
            let token = Token()
            captured = token
            receiver = self.receiver { _ in withExtendedLifetime(token) {} }
        }
        receiver.deliver(Self.pixelBuffer(), presentationSeconds: 1)
        #expect(captured != nil)

        receiver.disable()
        #expect(captured == nil)
    }

    /// Regression: the handler used to sit bare in the lock and gained two thunk layers per frame, so disabling
    /// after a few thousand frames overflowed a dispatch thread's stack and crashed the app. Runs on a thread with
    /// that 512 KB stack; with the old storage this test crashes instead of failing.
    @Test func disableAfterManyFramesDoesNotOverflowADispatchSizedStack() {
        let count = OSAllocatedUnfairLock(initialState: 0)
        let receiver = receiver { _ in count.withLock { $0 += 1 } }
        let finished = DispatchSemaphore(value: 0)

        let thread = Thread {
            let buffer = Self.pixelBuffer()
            for index in 0..<20_000 {
                receiver.deliver(buffer, presentationSeconds: Double(index))
            }
            receiver.disable()
            finished.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        finished.wait()

        #expect(count.withLock { $0 } == 20_000)
    }
}
