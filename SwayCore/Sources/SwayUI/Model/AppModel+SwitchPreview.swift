import Foundation
import SwayModels

// The live Switch preview (SPEC F11): every live sample goes through the engine's decider, and a completed dwell
// moves a *simulated* focus and adds a log line. The preview never calls `focus.focus(...)`.
extension AppModel {
    /// Most would-be switches kept in the log.
    static let switchLogLimit = 10

    /// True while samples should feed the decider: Live is on, no gate test is steering the camera, and a profile
    /// exists. (A gate test's stream carries landmarks and deliberate looks; neither belongs in the preview.)
    var isSwitchPreviewActive: Bool {
        liveEnabled && gateRunState == .idle && calibrationProfile != nil
    }

    /// Makes a fresh decider for the current profile and clears the preview. Called when the profile changes and
    /// when Live starts.
    func rebuildDecider() {
        decider = calibrationProfile.map { engine.makeDecider(profile: $0, settings: .default) }
        clearPreviewState()
    }

    /// Drops any dwell or cooldown and forgets the simulated focus: after a layout change, a stream restart or
    /// interruption, or when the camera stops.
    func resetSwitchPreview() {
        decider?.reset()
        clearPreviewState()
    }

    private func clearPreviewState() {
        dwellStart = nil
        if simulatedFocus != nil { simulatedFocus = nil }
        if previewDecision != nil { previewDecision = nil }
    }

    /// Runs one live sample through the decider with the simulated focus and lock.
    func processSwitchPreview(_ sample: PoseSample) {
        guard isSwitchPreviewActive, decider != nil else { return }
        let context = SwitchContext(focusedDisplay: simulatedFocus, isFocusLocked: simulateFocusLock, targets: nil)
        guard let decision = decider?.process(sample, context: context) else { return }
        trackDwell(decision, at: sample.timestamp)
        if let target = decision.switchTo { recordSwitch(to: target, at: sample.timestamp) }
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

    /// Moves the simulated focus and logs the switch with its dwell latency.
    private func recordSwitch(to target: DisplayID, at timestamp: TimeInterval) {
        // With a dwell of zero a switch fires without a dwelling phase ever being seen: no latency then.
        let start = dwellStart.flatMap { $0.display == target ? $0.timestamp : nil } ?? timestamp
        dwellStart = nil
        simulatedFocus = target
        switchLog.insert(
            SwitchLogEntry(
                id: takeLogID(), time: environment.now(), displayName: displayName(for: target),
                latency: max(0, timestamp - start)),
            at: 0)
        if switchLog.count > Self.switchLogLimit { switchLog.removeLast(switchLog.count - Self.switchLogLimit) }
    }

    /// A fresh id for the next log row. Both logs draw from one counter, so ids are unique within the model.
    func takeLogID() -> Int {
        nextLogID += 1
        return nextLogID
    }

    /// The unique label of display `id` in the current layout, falling back to the names in the latest analysis.
    func displayName(for id: DisplayID) -> String {
        DisplayLabeler.labels(for: layout)[id] ?? analysisLabels[id] ?? "Unknown display"
    }
}
