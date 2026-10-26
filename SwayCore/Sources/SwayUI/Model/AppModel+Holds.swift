import Foundation

// Switching waits while the displays or the Spaces change (SPEC D44, CONTRACT 6.5.5 item 1). While either holds, the
// decider is told it is locked, so it drops any dwell and no switch fires. Both are invisible in the menu. The timers
// come from the injected scheduler, so tests never sleep.
extension AppModel {
    /// Longest a display change holds when no new layout arrives, in seconds.
    static let displaysChangingTimeout: TimeInterval = 0.75
    /// How long a Space change holds, in seconds.
    static let spaceChangingDuration: TimeInterval = 0.6

    // MARK: Displays

    /// The screen parameters changed: displays were plugged, unplugged, or rearranged. The new layout reaches
    /// ``layoutDidChange(_:)`` a little later (the display tracker settles first), and until then the believed focus
    /// and any dwell mean nothing.
    ///
    /// Resets the loop as a layout change does, which also drops a switch in flight (its late result is ignored). A
    /// further notification restarts the wait.
    func displayParametersDidChange() {
        resetTracking()
        if !displaysChanging { displaysChanging = true }
        displaysChangingTimer?.cancel()
        displaysChangingTimer = environment.scheduler.schedule(after: Self.displaysChangingTimeout) { [weak self] in
            self?.endDisplaysChanging()
        }
    }

    /// The new layout is known, or the wait ran out: switching may resume, after one look at where focus is.
    func endDisplaysChanging() {
        displaysChangingTimer?.cancel()
        displaysChangingTimer = nil
        guard displaysChanging else { return }
        displaysChanging = false
        if isPollingFocus { pollFocusedDisplay() }
    }

    // MARK: Spaces

    /// The active Space changed. What the window server reports as the front window is still settling, so switching
    /// holds for a moment, and a focus poll already running may have seen the old Space: it is dropped.
    func activeSpaceDidChange() {
        trackingPollTask?.cancel()
        trackingPollTask = nil
        if !spaceChanging { spaceChanging = true }
        spaceChangingTimer?.cancel()
        spaceChangingTimer = environment.scheduler.schedule(after: Self.spaceChangingDuration) { [weak self] in
            self?.endSpaceChanging()
        }
    }

    /// The Space has settled: switching may resume, after one look at where focus is.
    func endSpaceChanging() {
        spaceChangingTimer?.cancel()
        spaceChangingTimer = nil
        guard spaceChanging else { return }
        spaceChanging = false
        if isPollingFocus { pollFocusedDisplay() }
    }

    /// Drops both holds and their timers (quitting).
    func cancelDisplayAndSpaceHolds() {
        displaysChangingTimer?.cancel()
        displaysChangingTimer = nil
        spaceChangingTimer?.cancel()
        spaceChangingTimer = nil
        if displaysChanging { displaysChanging = false }
        if spaceChanging { spaceChanging = false }
    }
}
