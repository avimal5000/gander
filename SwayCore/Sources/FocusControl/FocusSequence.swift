import Foundation
import SwayModels

/// The focus fallback list, independent of how windows are found and raised:
/// 1. `accessibilityRaise`: raise the window, make it main, make its app frontmost, then verify.
/// 2. `appActivation`: ask the system to activate the app, raise again, then verify.
/// Each method is verified by polling. If both fail the sequence reports `focusDidNotMove`.
struct FocusSequence<Platform: FocusPlatform>: Sendable {
    let platform: Platform
    let polling: FocusPolling

    init(platform: Platform, polling: FocusPolling = .standard) {
        self.platform = platform
        self.polling = polling
    }

    /// Runs the fallback list for `target`.
    func run(target: WindowSummary) async -> FocusSequenceOutcome {
        guard let handle = await platform.prepare(target) else { return .windowNotFound }
        let summary = target.settingTitle(platform.title(of: handle))

        await platform.raise(handle)
        if await waitUntilFocused(handle) { return .focused(summary, .accessibilityRaise) }
        if Task.isCancelled { return .cancelled }

        await platform.activateApplication(processID: target.processID)
        await platform.raise(handle)
        if await waitUntilFocused(handle) { return .focused(summary, .appActivation) }
        return Task.isCancelled ? .cancelled : .focusDidNotMove(summary)
    }

    /// Checks right away, then every `polling.interval`, until focus is verified or `polling.timeout` passes.
    private func waitUntilFocused(_ handle: Platform.Handle) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: polling.timeout)
        while true {
            if await platform.isFocused(handle) { return true }
            let remaining = clock.now.duration(to: deadline)
            if remaining <= .zero || Task.isCancelled { return false }
            try? await Task.sleep(for: min(polling.interval, remaining))
        }
    }
}
