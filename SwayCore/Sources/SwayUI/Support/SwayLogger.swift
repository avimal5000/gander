import SwayModels
import os

/// Loggers for this module (CONTRACT 9: category `ui`, and `tracking` for the M4 loop).
enum SwayLogger {
    static let ui = SwayLog.logger(category: "ui")
    static let tracking = SwayLog.logger(category: "tracking")
}
