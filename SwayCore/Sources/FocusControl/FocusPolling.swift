/// How long and how often the focus sequence checks that focus really moved.
struct FocusPolling: Sendable, Equatable {
    /// Time between checks.
    var interval: Duration
    /// Longest wait per method before giving up on it.
    var timeout: Duration

    /// 25 ms steps for up to 300 ms.
    static let standard = FocusPolling(interval: .milliseconds(25), timeout: .milliseconds(300))
}
