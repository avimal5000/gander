import Foundation

// Switching waits while the displays or the Spaces change (SPEC D44, CONTRACT 6.5.5 item 1). While either holds, the
// decider is told it is locked, so it drops any dwell and no switch fires. Both are invisible in the menu. The timers
// come from the injected scheduler, so tests never sleep. Each hold is logged when it starts and when it ends: which
// hold, how long it lasted, and what ended it.
extension AppModel {
    /// Longest a display change holds when no new layout arrives, in seconds.
    static let displaysChangingTimeout: TimeInterval = 0.75
    /// Longest a display hold lasts from its first notification, however many follow, in seconds.
    static let displaysChangingCap: TimeInterval = 3
    /// How long a Space change holds, in seconds.
    static let spaceChangingDuration: TimeInterval = 0.6

    // MARK: Displays

    /// The screen parameters changed: displays were plugged, unplugged, or rearranged. The new layout reaches
    /// ``layoutDidChange(_:)`` a little later (the display tracker settles first), and until then the believed focus
    /// and any dwell mean nothing.
    ///
    /// Resets the loop as a layout change does, which also drops a switch in flight (its late result is ignored). A
    /// further notification restarts the wait, but never past ``displaysChangingCap`` seconds from the first one: a
    /// display that keeps posting without changing its layout must not stop switching for good. After the cap, the same
    /// chatter is ignored (no hold, no reset) until it pauses for the timeout.
    func displayParametersDidChange() {
        let now = environment.clock()
        let previous = lastDisplayNotification
        lastDisplayNotification = now
        if displaysHoldCapped {
            if let previous, now - previous < Self.displaysChangingTimeout { return }
            displaysHoldCapped = false
        }
        resetTracking()
        if !displaysChanging {
            displaysChanging = true
            displaysHoldStart = now
            GanderLogger.tracking.info("\(HoldLog.started(.displays), privacy: .public)")
        }
        let remaining = Self.displaysChangingCap - (now - (displaysHoldStart ?? now))
        let reachesCap = remaining < Self.displaysChangingTimeout
        displaysChangingTimer?.cancel()
        displaysChangingTimer = environment.scheduler.schedule(
            after: reachesCap ? max(0, remaining) : Self.displaysChangingTimeout
        ) { [weak self] in
            self?.endDisplaysChanging(by: reachesCap ? .cap : .timeout)
        }
    }

    /// The new layout is known, or the wait ran out: switching may resume, after one look at where focus is.
    func endDisplaysChanging(by end: HoldLog.End) {
        displaysChangingTimer?.cancel()
        displaysChangingTimer = nil
        guard displaysChanging else { return }
        displaysChanging = false
        if end == .cap { displaysHoldCapped = true }
        let lasted = environment.clock() - (displaysHoldStart ?? environment.clock())
        displaysHoldStart = nil
        GanderLogger.tracking.info("\(HoldLog.ended(.displays, by: end, after: lasted), privacy: .public)")
        if isPollingFocus { pollFocusedDisplay() }
    }

    // MARK: Spaces

    /// The active Space changed. What the window server reports as the front window is still settling, so switching
    /// holds for a moment, and a focus poll already running may have seen the old Space: it is dropped.
    func activeSpaceDidChange() {
        trackingPollTask?.cancel()
        trackingPollTask = nil
        if !spaceChanging {
            spaceChanging = true
            spaceHoldStart = environment.clock()
            GanderLogger.tracking.info("\(HoldLog.started(.space), privacy: .public)")
        }
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
        let lasted = environment.clock() - (spaceHoldStart ?? environment.clock())
        spaceHoldStart = nil
        GanderLogger.tracking.info("\(HoldLog.ended(.space, by: .timeout, after: lasted), privacy: .public)")
        if isPollingFocus { pollFocusedDisplay() }
    }

    /// Drops both holds and their timers (quitting).
    func cancelDisplayAndSpaceHolds() {
        displaysChangingTimer?.cancel()
        displaysChangingTimer = nil
        spaceChangingTimer?.cancel()
        spaceChangingTimer = nil
        displaysHoldStart = nil
        spaceHoldStart = nil
        displaysHoldCapped = false
        if displaysChanging { displaysChanging = false }
        if spaceChanging { spaceChanging = false }
    }
}
