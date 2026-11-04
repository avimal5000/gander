import Foundation
import GanderModels

/// The focus fallback list, independent of how windows are found and raised:
/// 1. `appActivation`: raise the window and make it main, then ask the system to activate its app, then verify.
///    Activation brings only the raised window forward, or at worst the app's main and key windows, so its other
///    windows stay behind whatever covers them (SPEC D42, D53).
/// 2. `accessibilityFrontmost`: make the app frontmost through Accessibility, raise again, then verify. That can
///    bring all of the app's windows forward, so it is only the fallback for an app that ignores activation.
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
        await platform.activateApplication(processID: target.processID)
        if await waitUntilFocused(handle) { return .focused(summary, .appActivation) }
        if Task.isCancelled { return .cancelled }

        await platform.makeFrontmost(handle)
        await platform.raise(handle)
        if await waitUntilFocused(handle) { return .focused(summary, .accessibilityFrontmost) }
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
