import SwayModels

/// How a focus sequence ended, before timing and logging.
enum FocusSequenceOutcome: Sendable, Equatable {
    /// Verified. The summary carries the Accessibility title when known.
    case focused(WindowSummary, FocusMethod)
    /// The window could not be found through Accessibility.
    case windowNotFound
    /// Both methods were tried and verification failed.
    case focusDidNotMove(WindowSummary)
    /// The caller's task was cancelled mid-sequence.
    case cancelled

    /// The public result for `target`, the window the sequence was asked to focus.
    func result(for target: WindowSummary, milliseconds: Int) -> FocusResult {
        switch self {
        case .focused(let summary, let method):
            return .focused(summary, method: method, milliseconds: milliseconds)
        case .windowNotFound:
            return .failed(target, reason: "Window not found through Accessibility")
        case .focusDidNotMove(let summary):
            return .failed(summary, reason: "Focus did not move to \(summary.appName)")
        case .cancelled:
            return .failed(target, reason: "Cancelled")
        }
    }
}
