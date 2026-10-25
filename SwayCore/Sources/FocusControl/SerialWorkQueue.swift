import Dispatch

/// The one private serial queue that runs every window-list and Accessibility call, so none of them touch the
/// main thread. Bridges blocking work to async code.
final class SerialWorkQueue: Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    /// Runs `work` on the queue and resumes with its result. Not cancellable: `work` always runs to completion.
    func run<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
