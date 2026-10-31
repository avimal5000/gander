import GanderModels
import os

/// Loggers for this module (CONTRACT 9: category `ui`, and `tracking` for the M4 loop).
enum GanderLogger {
    static let ui = GanderLog.logger(category: "ui")
    static let tracking = GanderLog.logger(category: "tracking")
}
