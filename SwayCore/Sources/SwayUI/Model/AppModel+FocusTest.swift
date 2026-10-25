import Foundation
import SwayModels

// The Focus Test window (SPEC F12, F13): Accessibility onboarding, the last-used window per display, and one-at-a-time
// focus requests, immediately or after a 3 s countdown. While the window is open, one timer drives the countdown and
// a once-a-second refresh; both read the injected clock, so tests move time by hand and call `focusTick()`.
extension AppModel {
    /// Seconds between "Focus in 3 s" and the request.
    static let delayedFocusSeconds: TimeInterval = 3
    /// Seconds between refreshes of trust, windows, and the focused display while the window is open.
    static let focusPollInterval: TimeInterval = 1
    /// Most results kept in the log.
    static let focusLogLimit = 10

    /// True when a focus request may start: Accessibility is granted and nothing else is pending or running.
    var canRequestFocus: Bool { isAccessibilityTrusted && focusActivity == .idle }

    // MARK: Window lifecycle

    /// The Focus Test window opened: start refreshing. Ignored for the copy SwiftUI opens at launch, which the
    /// launch guard closes unseen (nobody asked for it).
    func startFocusTest() {
        guard hasWindowRequest(SwayWindowID.focusTest), !focusTestVisible else { return }
        focusTestVisible = true
        nextFocusPoll = environment.clock() + Self.focusPollInterval
        startFocusTimer()
        refreshFocusTest()
    }

    /// The Focus Test window closed (or the app is quitting): stop polling, drop a pending countdown, cancel a request
    /// in flight (the controller then tries no further method), and forget the window list, so titles are held only
    /// while the window shows them.
    func stopFocusTest() {
        focusTestVisible = false
        focusTickTask?.cancel()
        focusTickTask = nil
        focusPollTask?.cancel()
        focusPollTask = nil
        focusPollGeneration += 1
        focusRequestTask?.cancel()
        if case .countingDown = focusActivity { focusActivity = .idle }
        if !focusWindows.isEmpty { focusWindows = [:] }
        if focusedDisplayID != nil { focusedDisplayID = nil }
    }

    private func startFocusTimer() {
        focusTickTask?.cancel()
        guard let interval = environment.focusTickInterval else { return }
        focusTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.focusTick()
            }
        }
    }

    /// Advances time-driven work: fires or updates a countdown, and refreshes once a second. Called by the focus
    /// timer; tests call it after moving their clock. Does nothing unless the window is open.
    func focusTick() {
        guard focusTestVisible else { return }
        let now = environment.clock()
        if case .countingDown(let display, let deadline) = focusActivity {
            if now >= deadline {
                focusActivity = .idle
                beginFocus(display)
            } else {
                let remaining = Int((deadline - now).rounded(.up))
                if remaining != focusCountdownSeconds { focusCountdownSeconds = remaining }
            }
        }
        if now >= nextFocusPoll {
            nextFocusPoll = now + Self.focusPollInterval
            refreshFocusTest()
        }
    }

    // MARK: Refresh

    /// Reads Accessibility trust, then the last-used windows and focused display. The window refresh is skipped
    /// while the previous one is still running, so slow Accessibility calls never pile up.
    func refreshFocusTest() {
        let trusted = focus.isTrusted()
        if trusted != isAccessibilityTrusted { isAccessibilityTrusted = trusted }
        guard focusPollTask == nil else { return }
        focusPollGeneration += 1
        let generation = focusPollGeneration
        let layout = layout
        focusPollTask = Task { [weak self, focus] in
            let windows = await focus.lastUsedWindows(in: layout)
            let focused = await focus.focusedDisplay(in: layout)
            // A closed window bumps the generation and cancels this task; its late answer is dropped.
            guard !Task.isCancelled, let self, generation == self.focusPollGeneration else { return }
            self.focusPollTask = nil
            if windows != self.focusWindows { self.focusWindows = windows }
            if focused != self.focusedDisplayID { self.focusedDisplayID = focused }
        }
    }

    // MARK: Requests

    /// "Focus": raise the last-used window on `display` now. Ignored while another request is pending or running.
    func focusNow(_ display: DisplayID) {
        guard focusActivity == .idle else { return }
        beginFocus(display)
    }

    /// "Focus in 3 s": counts down on the injected clock, so the user can click into another app first.
    func focusAfterDelay(_ display: DisplayID) {
        guard canRequestFocus else { return }
        focusCountdownSeconds = Int(Self.delayedFocusSeconds)
        focusActivity = .countingDown(display: display, deadline: environment.clock() + Self.delayedFocusSeconds)
    }

    /// Cancels a pending "Focus in 3 s".
    func cancelDelayedFocus() {
        guard case .countingDown = focusActivity else { return }
        focusActivity = .idle
    }

    /// Starts one request. Without Accessibility nothing is attempted and the log says so.
    private func beginFocus(_ display: DisplayID) {
        guard isAccessibilityTrusted else {
            appendFocusLog("Accessibility permission needed")
            return
        }
        focusActivity = .focusing(display: display)
        let layout = layout
        focusRequestTask = Task { [weak self, focus] in
            let result = await focus.focus(display: display, in: layout)
            self?.finishFocus(result)
        }
    }

    private func finishFocus(_ result: FocusResult) {
        appendFocusLog(FocusTestPresentation.logText(for: result, displayName: { displayName(for: $0) }))
        if case .notTrusted = result { isAccessibilityTrusted = false }
        focusActivity = .idle
        focusRequestTask = nil
        // Show the outcome at once instead of up to a second later.
        if focusTestVisible { refreshFocusTest() }
    }

    private func appendFocusLog(_ text: String) {
        focusLog.insert(FocusLogEntry(id: takeLogID(), time: environment.now(), text: text), at: 0)
        if focusLog.count > Self.focusLogLimit { focusLog.removeLast(focusLog.count - Self.focusLogLimit) }
    }

    // MARK: Accessibility onboarding

    /// "Grant Access…": asks for trust (the system shows its prompt at most once per launch), then opens the
    /// Accessibility pane of System Settings. The status turns to granted on the next refresh.
    func grantAccessibility() {
        focus.requestTrust()
        environment.system.openAccessibilityPrivacySettings()
    }
}
