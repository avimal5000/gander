import Foundation

/// Polls `condition` every few milliseconds until it holds or `timeout` passes. Returns whether it held.
/// Used only to wait for work that finishes on another task; a healthy run returns within a few polls.
func waitUntil(timeout: Duration = .seconds(1), _ condition: @Sendable () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
