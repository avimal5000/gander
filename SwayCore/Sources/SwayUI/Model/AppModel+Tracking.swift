import Foundation
import SwayModels

// The automatic tracking loop (SPEC F16, D28, D29): every pose sample goes through the switch decider; when it fires,
// Sway focuses the last-used window on that display. `TrackingLoop` holds the pure bookkeeping (which display has
// focus, what is in flight); this extension feeds it and does the I/O. The focused display is polled once a second
// and on every app activation, and only while the camera runs for tracking.
extension AppModel {
    /// Most switches kept in the log.
    static let switchLogLimit = 10
    /// Seconds between focused-display polls while tracking runs.
    static let focusedDisplayPollInterval: TimeInterval = 1

    // MARK: State

    /// Why automatic switching is held right now, if it is: the first that applies of Focus Lock, Sway being the
    /// active app, a Focus Test request, the displays or the Spaces changing (SPEC D44), and Sway's own request in
    /// flight.
    var trackingHold: TrackingHold? {
        if focusLocked { return .focusLock }
        if isAppActive { return .swayInFront }
        if focusActivity != .idle { return .focusTest }
        if displaysChanging { return .displaysChanging }
        if spaceChanging { return .spaceChanging }
        if isSwitching { return .switching }
        return nil
    }

    /// True while samples feed the decider: Tracking is on, no gate test or calibration is steering the camera, the
    /// Setup window is not on its camera check, calibration, or result, and a calibration fits. (Those looks are
    /// deliberate and the user is adjusting Sway; neither belongs in the loop.)
    var isTrackingActive: Bool {
        trackingEnabled && gateRunState == .idle && !isSetupHoldingTracking && activeCalibration != nil
            && decider != nil
    }

    // MARK: User action

    /// The Tracking switch. The choice is saved, so the next launch restores it; turning it on may first show the
    /// camera permission explanation.
    func setTrackingEnabled(_ enabled: Bool) async {
        guard enabled != trackingEnabled else { return }
        defaults.set(enabled, forKey: DefaultsKey.trackingEnabled)
        trackingEnabled = enabled
        if !enabled, pendingIntent == .tracking { pendingIntent = nil }
        resetTracking()
        syncTrackingActivity()
        await reconcileCamera().value
    }

    // MARK: Decider

    /// Makes a fresh decider for the active calibration and clears the loop. Called when the calibration changes,
    /// when a tracking stream starts, and when the sensitivity changes.
    func rebuildDecider() {
        let settings = sensitivity.switchSettings()
        enterMargin = settings.enterMargin
        if let match = activeCalibration {
            decider = engine.makeDecider(profile: match.profile, settings: settings)
        } else {
            decider = nil
        }
        updateTrackedTargets()
        clearTrackingState()
        if isPollingFocus { pollFocusedDisplay() }
    }

    /// The first `SwayPolicy.maxTrackedDisplays` calibrated displays of the layout (SPEC D22), or `nil` for all.
    func updateTrackedTargets() {
        trackedTargets = activeCalibration.flatMap {
            TrackingLoop.targets(layout: layout, profile: $0.profile, limit: SwayPolicy.maxTrackedDisplays)
        }
    }

    /// Drops any dwell or cooldown and forgets the focus bookkeeping: after a layout change, a stream restart or
    /// interruption, or when the camera stops.
    func resetTracking() {
        decider?.reset()
        clearTrackingState()
    }

    private func clearTrackingState() {
        loop.reset()
        focusSwitchTask?.cancel()
        focusSwitchTask = nil
        trackingPollTask?.cancel()
        trackingPollTask = nil
        dwellStart = nil
        if previewDecision != nil { previewDecision = nil }
        if lookSummary != .off { lookSummary = .off }
        syncLoopState()
    }

    /// Copies the loop's focus facts into the observed mirrors, only when they changed.
    func syncLoopState() {
        let focused = loop.focusedDisplay
        if focused != trackingFocus { trackingFocus = focused }
        let busy = loop.isFocusing
        if busy != isSwitching { isSwitching = busy }
    }

    /// Saves and applies new switching settings (SPEC D31).
    func setSensitivity(_ newValue: SwitchSensitivity) {
        let clamped = SwitchSensitivity(dwell: newValue.dwell, confidenceLevel: newValue.confidenceLevel)
        guard clamped != sensitivity else { return }
        sensitivity = clamped
        if let data = try? Self.encoder().encode(clamped) {
            defaults.set(data, forKey: DefaultsKey.switchSensitivity)
        }
        rebuildDecider()
    }

    /// The stored settings, or the defaults when absent or unreadable. Values are clamped into range.
    static func storedSensitivity(in defaults: UserDefaults) -> SwitchSensitivity {
        guard let data = defaults.data(forKey: DefaultsKey.switchSensitivity),
            let stored = try? decoder().decode(SwitchSensitivity.self, from: data)
        else { return .default }
        return SwitchSensitivity(dwell: stored.dwell, confidenceLevel: stored.confidenceLevel)
    }

    // MARK: Per sample

    /// Runs one tracked sample through the decider with the loop's focus and holds, and acts on its decision. Only a
    /// camera that reports running switches: a sample that arrives after the status left running (an interruption, a
    /// suspension) is stale.
    func processTracking(_ sample: PoseSample) {
        guard status.isRunning, isTrackingActive else { return }
        // Sway's own request in flight is not a lock: a lock cancels the decider's cooldown, which must run from the
        // switch. The loop already reports the target as focused and refuses a second request.
        let hold = trackingHold
        let context = SwitchContext(
            focusedDisplay: loop.focusedDisplay, isFocusLocked: hold != nil && hold != .switching,
            targets: trackedTargets)
        guard let decision = decider?.process(sample, context: context) else { return }
        trackDwell(decision, at: sample.timestamp)
        updateLookSummary(decision.classification)
        loop.lookChanged(to: decision.classification, enterMargin: enterMargin)
        syncLoopState()
        if let target = decision.switchTo { requestSwitch(to: target, at: sample.timestamp) }
        if decision != previewDecision { previewDecision = decision }
    }

    /// Remembers where each dwell began. The start is the first sample of a dwelling phase on a display; any other
    /// phase (idle, locked) means the dwell was lost.
    ///
    /// A dwell starts at progress 0. That also marks a dwell begun again on the same display without an idle phase
    /// in between: after a gap longer than `maxGap`, the decider drops the old dwell and starts a fresh one on the
    /// same sample (CONTRACT 6.6 step 4(a2)), so the latency must count from that sample, not the old start.
    private func trackDwell(_ decision: SwitchDecision, at timestamp: TimeInterval) {
        switch decision.phase {
        case .dwelling(let display, let progress):
            if dwellStart?.display != display || progress == 0 { dwellStart = (display, timestamp) }
        case .idle, .locked:
            dwellStart = nil
        case .coolingDown:
            break
        }
    }

    private func updateLookSummary(_ classification: PoseClassification) {
        let summary = LookSummary(classification) { displayLabels[$0] ?? displayName(for: $0) }
        if summary != lookSummary { lookSummary = summary }
    }

    // MARK: Focus requests

    /// The decider fired: move focus to the last-used window on `target`, one request at a time.
    private func requestSwitch(to target: DisplayID, at timestamp: TimeInterval) {
        // With a dwell of zero a switch fires without a dwelling phase ever being seen: no hold time then.
        let start = dwellStart.flatMap { $0.display == target ? $0.timestamp : nil } ?? timestamp
        dwellStart = nil
        let held = max(0, timestamp - start)
        // Held (the decider already knows), or without Accessibility there is nothing to ask for: the status says
        // "Needs Accessibility".
        guard trackingHold == nil, isAccessibilityTrusted, loop.beginAttempt(target) else { return }
        syncLoopState()
        let epoch = loop.epoch
        let layout = layout
        focusSwitchTask = Task { [weak self, focus] in
            let result = await focus.focus(display: target, in: layout)
            self?.finishSwitch(to: target, result: result, held: held, epoch: epoch)
        }
    }

    /// A focus request ended. Ignored when tracking stopped or the loop was reset since it began.
    private func finishSwitch(to target: DisplayID, result: FocusResult, held: TimeInterval, epoch: Int) {
        guard epoch == loop.epoch, loop.inFlight == target else { return }
        focusSwitchTask = nil
        loop.finishAttempt(target, result: result)
        syncLoopState()
        if case .notTrusted = result, isAccessibilityTrusted {
            isAccessibilityTrusted = false
            syncPoseDemand()
        }
        let display = displayName(for: target)
        appendSwitchLog(SwitchPreviewPresentation.logText(for: result, display: display, held: held))
        logSwitch(result, display: display)
        // The glow marks a switch that really moved focus, and only Sway's own tracking requests come through here.
        if case .focused = result { showEdgeGlow(on: target) }
    }

    private func appendSwitchLog(_ text: String) {
        switchLog.insert(SwitchLogEntry(id: takeLogID(), time: environment.now(), text: text), at: 0)
        if switchLog.count > Self.switchLogLimit { switchLog.removeLast(switchLog.count - Self.switchLogLimit) }
    }

    /// One info line per switch: the outcome, the app, the display, the method, and the time. Never a window title.
    private func logSwitch(_ result: FocusResult, display: String) {
        let log = SwayLogger.tracking
        switch result {
        case .focused(let window, let method, let milliseconds):
            log.info(
                "Focused \(window.appName, privacy: .public) on \(display, privacy: .public) via \(method.rawValue, privacy: .public) in \(milliseconds) ms"
            )
        case .noWindow:
            log.info("No window on \(display, privacy: .public)")
        case .notTrusted:
            log.info("Switch needs Accessibility permission")
        case .failed(let window, let reason):
            log.info(
                "Switch to \(display, privacy: .public) failed (\(window?.appName ?? "no app", privacy: .public)): \(reason, privacy: .public)"
            )
        }
    }

    /// A fresh id for the next log row. Both logs draw from one counter, so ids are unique within the model.
    func takeLogID() -> Int {
        nextLogID += 1
        return nextLogID
    }

    /// The unique label of display `id` in the current layout, falling back to the names in the latest analysis.
    func displayName(for id: DisplayID) -> String {
        displayLabels[id] ?? analysisLabels[id] ?? "Unknown display"
    }

    // MARK: Focused-display poll

    /// Starts or stops the focused-display poll to match whether the camera runs for tracking, and keeps the pose
    /// demand and the camera fallback in step with the state. Cheap to call.
    func syncTrackingActivity() {
        syncFocusedDisplayPoll()
        // After the poll: its first step reads Accessibility, which the pose demand depends on.
        syncPoseDemand()
        syncCameraFallback()
    }

    private func syncFocusedDisplayPoll() {
        let shouldPoll = isTrackingActive && status.isRunning
        guard shouldPoll != isPollingFocus else { return }
        isPollingFocus = shouldPoll
        if shouldPoll {
            startTrackingTimer()
            trackingTick()
        } else {
            trackingTickTask?.cancel()
            trackingTickTask = nil
            trackingPollTask?.cancel()
            trackingPollTask = nil
        }
    }

    private func startTrackingTimer() {
        trackingTickTask?.cancel()
        guard let interval = environment.trackingTickInterval else { return }
        trackingTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.trackingTick()
            }
        }
    }

    /// One poll step: refresh Accessibility trust, then ask where focus is, unless the last question is still
    /// running. The timer calls this once a second; tests call it directly. Does nothing unless tracking runs.
    func trackingTick() {
        guard isPollingFocus else { return }
        refreshAccessibilityTrust()
        pollFocusedDisplay()
    }

    /// Asks `focus` which display holds the focused window. Also called on every app activation. An answer is
    /// ignored if a request began or ended, or the loop was reset, while the question was running.
    func pollFocusedDisplay() {
        guard isPollingFocus, trackingPollTask == nil else { return }
        let epoch = loop.pollStarted()
        let layout = layout
        trackingPollTask = Task { [weak self, focus] in
            let display = await focus.focusedDisplay(in: layout)
            guard !Task.isCancelled, let self else { return }
            self.trackingPollTask = nil
            self.loop.pollFinished(display, epoch: epoch)
            self.syncLoopState()
        }
    }

    /// Reads Accessibility trust (never prompts) into `isAccessibilityTrusted`, assigning only on a change.
    func refreshAccessibilityTrust() {
        let trusted = focus.isTrusted()
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        // Missing Accessibility lowers the frame rate (nothing can switch), granting it raises it again.
        syncPoseDemand()
    }
}
