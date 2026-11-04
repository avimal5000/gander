import GanderModels

/// The bookkeeping of the automatic tracking loop (SPEC F16, D29): which display has keyboard focus as far as the
/// decider should believe, whether a focus request is running, and when a late answer must be dropped.
///
/// Pure: no I/O and no clock. `AppModel` feeds it the answers of the focused-display poll and of the focus requests.
///
/// The focused display is the first of three sources that is known:
/// 1. `inFlight`: the display a focus request is moving focus to right now;
/// 2. `override`: a display Gander treats as focused after a failed or "no window" attempt, so a look at a display
///    without a usable window does not retry every 0.75 s, and after an attempt that found the focused window already
///    showing there (SPEC D52), so a window that straddles two displays does not trigger an attempt on every look. It
///    ends when the real focus is seen elsewhere (a poll that differs from what it was before the attempt) or when the
///    look moves to another display;
/// 3. `polled`: the last accepted answer of the poll.
///
/// `epoch` counts everything that can make an in-progress poll or request out of date; a poll that started under an
/// older epoch is ignored when it finishes.
struct TrackingLoop: Equatable, Sendable {
    /// A display treated as focused after an attempt that did not move focus, and what focus was before it.
    struct Override: Equatable, Sendable {
        let display: DisplayID
        /// The focused display before the attempt. A poll that still says this one keeps the override.
        let before: DisplayID?
    }

    /// The last accepted poll result; `nil` when focus is unknown (or Gander itself is in front).
    private(set) var polled: DisplayID?
    private(set) var override: Override?
    /// The display of the focus request now running.
    private(set) var inFlight: DisplayID?
    private(set) var epoch = 0
    /// The focused display when the running attempt began; becomes the override's `before` if it fails.
    private var attemptBefore: DisplayID?

    init() {}

    /// What the decider should treat as the focused display.
    var focusedDisplay: DisplayID? { inFlight ?? override?.display ?? polled }

    /// True while a focus request runs. No other request may start.
    var isFocusing: Bool { inFlight != nil }

    /// Starts a request for `display`. Returns false, changing nothing, when one is already running.
    @discardableResult
    mutating func beginAttempt(_ display: DisplayID) -> Bool {
        guard inFlight == nil else { return false }
        attemptBefore = focusedDisplay
        inFlight = display
        epoch += 1
        return true
    }

    /// Ends the running request with its outcome.
    mutating func finishAttempt(_ display: DisplayID, result: FocusResult) {
        let before = attemptBefore
        inFlight = nil
        attemptBefore = nil
        epoch += 1
        switch result {
        case .focused(_, .alreadyFocused, _):
            // Nothing moved. The poll may keep naming the display before the attempt (the window straddles displays
            // and most of it is there), so hold this display until focus really moves or the look does.
            override = Override(display: display, before: before)
        case .focused:
            polled = display
            override = nil
        case .noWindow, .failed:
            override = Override(display: display, before: before)
        case .notTrusted:
            break
        }
    }

    /// Marks the start of a focused-display poll. Hand the returned epoch to ``pollFinished(_:epoch:)``.
    func pollStarted() -> Int {
        epoch
    }

    /// Applies a poll result, unless a request began or ended, or the loop was reset, since the poll started.
    mutating func pollFinished(_ display: DisplayID?, epoch pollEpoch: Int) {
        guard pollEpoch == epoch, inFlight == nil else { return }
        if let override, display == override.before { return }
        override = nil
        polled = display
    }

    /// The latest classification of the look. A confident look at a display other than the override's ends the
    /// override: the user has moved on, so a new attempt there is allowed.
    mutating func lookChanged(to classification: PoseClassification, enterMargin: Double) {
        guard let override, classification.kind == .display, let best = classification.best,
            best != override.display, classification.margin >= enterMargin
        else { return }
        self.override = nil
    }

    /// Forgets everything, as after a layout change, a stream restart, or the camera stopping.
    mutating func reset() {
        polled = nil
        override = nil
        inFlight = nil
        attemptBefore = nil
        epoch += 1
    }
}

extension TrackingLoop {
    /// The displays focus may move to: the first `limit` displays of `layout`, in layout order, that `profile`
    /// profiles (SPEC D22). `nil` when that is every display the profile has, so the decider needs no restriction.
    static func targets(layout: DisplayLayout, profile: CalibrationProfile, limit: Int) -> Set<DisplayID>? {
        let profiled = profile.displayIDs
        let chosen = Set(layout.displays.map(\.id).filter { profiled.contains($0) }.prefix(limit))
        return chosen == profiled ? nil : chosen
    }
}
