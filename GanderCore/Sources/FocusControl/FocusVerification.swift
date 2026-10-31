/// The rule for deciding that focus really moved.
enum FocusVerification {
    /// True when the target's app is frontmost and its focused window is the target window.
    ///
    /// - Parameters:
    ///   - frontmostProcessID: The frontmost app's pid, `nil` if unknown.
    ///   - targetProcessID: The pid of the app that owns the target window.
    ///   - focusedWindowMatches: Whether the app's focused window equals the target window, or `nil` if the
    ///     focused window could not be read. Then the pid match alone is accepted.
    static func isVerified(frontmostProcessID: Int32?, targetProcessID: Int32, focusedWindowMatches: Bool?) -> Bool {
        guard frontmostProcessID == targetProcessID else { return false }
        return focusedWindowMatches ?? true
    }
}
