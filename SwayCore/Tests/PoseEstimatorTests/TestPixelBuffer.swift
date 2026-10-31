import CoreVideo
import Foundation
import SwayModels

/// Builds in-memory pixel buffers for tests. Nothing here touches a camera or the disk.
enum TestPixelBuffer {
    /// A black 32-bit BGRA buffer, 640x480 by default (the capture size Gander uses).
    static func blank(width: Int = 640, height: Int = 480) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            preconditionFailure("CVPixelBufferCreate failed with status \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// A frame around a blank buffer.
    static func frame(timestamp: TimeInterval) -> CameraFrame {
        CameraFrame(pixelBuffer: blank(), timestamp: timestamp)
    }
}
