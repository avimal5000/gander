import Foundation
import os

/// App-wide constants. Change behavior here, not with literals scattered across modules.
public enum SwayPolicy {
    public static let bundleIdentifier = "com.avimal5000.sway"
    /// Most displays tracking switches between (SPEC D22: raised from 2 after the M1 gate showed three displays
    /// separate cleanly). Logic stays generic over N displays and enforces the limit only through this constant.
    public static let maxTrackedDisplays = 3
    public static let defaultFrameRate: Double = 15
    public static let captureWidth = 640
    public static let captureHeight = 480
}

/// Local-only logging (PLAN.md: `os.Logger`, nothing leaves the Mac).
public enum SwayLog {
    public static let subsystem = SwayPolicy.bundleIdentifier

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
