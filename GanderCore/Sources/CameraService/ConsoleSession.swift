import CoreGraphics
import Foundation

/// Whether this login session is the one on the console (the one in front), read from the window server's session
/// dictionary. A session that is not on the console must not use the camera (D43).
enum ConsoleSession {
    /// True only when `sessionDictionary` says this session is not on the console. A missing dictionary (no GUI
    /// session) or a missing or malformed key means "assume console": the camera is not suspended.
    static func isInactive(sessionDictionary: [String: Any]?) -> Bool {
        guard let onConsole = sessionDictionary?[kCGSessionOnConsoleKey as String] as? Bool else { return false }
        return !onConsole
    }

    /// The live answer, from `CGSessionCopyCurrentDictionary()`.
    static func isInactiveNow() -> Bool {
        isInactive(sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any])
    }
}
