/// Retry budget for `AVCaptureSessionRuntimeError` (CONTRACT 6.1: retry once, then fail).
struct RuntimeRetryPolicy: Sendable, Equatable {
    /// What to do about a runtime error.
    enum Decision: Sendable, Equatable {
        case retry
        case fail
    }

    let maxRetries: Int
    private(set) var retriesUsed = 0

    init(maxRetries: Int = 1) {
        self.maxRetries = maxRetries
    }

    /// A runtime error happened. Spends one retry if any are left.
    mutating func errorOccurred() -> Decision {
        guard retriesUsed < maxRetries else { return .fail }
        retriesUsed += 1
        return .retry
    }

    /// Frames flowed again after a retry, so the budget is restored for a later, separate error.
    mutating func recovered() {
        retriesUsed = 0
    }

    /// A new capture run starts.
    mutating func reset() {
        retriesUsed = 0
    }
}
