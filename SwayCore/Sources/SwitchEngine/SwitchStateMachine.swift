import Foundation
import SwayModels
import os

/// The switch decider: classifies each sample and runs the dwell / cooldown state machine of CONTRACT
/// section 6.6 (SPEC F14).
///
/// Pure and deterministic. Time comes only from `PoseSample.timestamp`, so a recorded trace replays to the
/// same switches every time. Step numbers in the comments match the contract.
struct SwitchStateMachine: SwitchDeciding {
    /// `ε` of the contract, seconds. Timestamps are host uptime (about 3·10⁵ s), where a double only resolves
    /// about 6·10⁻¹¹ s, so the difference of two timestamps exactly 0.4 s apart can compute as 0.39999999996.
    /// Every time comparison therefore allows `ε` in the direction that meets its threshold, so a boundary frame
    /// is never one frame late.
    static let timeTolerance = 1e-6

    private enum State: Sendable, Equatable {
        case idle
        /// Holding a look at `display` since `start`; `lastSupport` is the last sample that supported it.
        case dwelling(display: DisplayID, start: Double, lastSupport: Double)
        case coolingDown(until: Double)
    }

    private let classifier: PoseClassifier
    private let settings: SwitchSettings
    private let log = SwayLog.logger(category: "engine")
    private var state = State.idle
    private var lastTimestamp: Double?

    init(profile: CalibrationProfile, settings: SwitchSettings) {
        classifier = PoseClassifier(profile: profile, settings: settings)
        self.settings = settings
    }

    mutating func reset() {
        state = .idle
        lastTimestamp = nil
    }

    mutating func process(_ sample: PoseSample, context: SwitchContext) -> SwitchDecision {
        let t = sample.timestamp

        // Step 0: time went backwards, so this is a new stream.
        if let last = lastTimestamp, t < last {
            log.debug("timestamp went backwards; decider reset")
            reset()
        }
        lastTimestamp = t

        // Step 1.
        let classification = classifier.classify(sample.pose)

        // Step 2: focus lock cancels everything, including a cooldown.
        if context.isFocusLocked {
            state = .idle
            return decision(.locked, reason: .focusLocked, classification)
        }

        // Step 3: cooldown. It is over when t >= until - ε.
        if case .coolingDown(let until) = state {
            if t < until - Self.timeTolerance {
                return decision(.coolingDown(until: until), reason: .coolingDown, classification)
            }
            state = .idle
        }

        // Step 4: an ongoing dwell may fire, continue, or be dropped (and then fall through to step 5).
        if case .dwelling(let target, let start, let lastSupport) = state,
            let result = continueDwell(
                on: target, start: start, lastSupport: lastSupport, at: t, classification, context)
        {
            return result
        }

        // Step 5: idle.
        return processIdle(at: t, classification, context)
    }

    // MARK: - Step 4

    /// Returns the decision for a sample that arrives while dwelling, or `nil` when the dwell ended without a
    /// decision and the sample should be handled as idle (steps 4(a), 4(a2), and 4(c)).
    private mutating func continueDwell(
        on target: DisplayID,
        start: Double,
        lastSupport: Double,
        at t: Double,
        _ classification: PoseClassification,
        _ context: SwitchContext
    ) -> SwitchDecision? {
        // (a) Focus already moved to the dwell target (for example by the user).
        if target == context.focusedDisplay {
            state = .idle
            return nil
        }

        // (a2) Too long since the last supporting sample: give up. This covers a run of non-supporting samples and
        // a hole in the stream (for example a camera stall) alike. The sample is then handled as idle, so it may
        // start a fresh dwell, and a stale dwell can never fire.
        if t - lastSupport > settings.maxGap + Self.timeTolerance {
            state = .idle
            return nil
        }

        // (b) The look is still supported at the lower stay margin.
        if classification.kind == .display, classification.best == target,
            classification.margin >= settings.stayMargin, isTarget(target, context)
        {
            state = .dwelling(display: target, start: start, lastSupport: t)
            if isDwellComplete(after: t - start) {
                return fire(target, at: t, classification)
            }
            return decision(
                .dwelling(display: target, progress: progress(since: start, at: t)),
                reason: .dwelling, classification)
        }

        // (c) A confident look at another display replaces the dwell (step 5 may start a new one).
        if let other = eligibleDisplay(classification, margin: settings.enterMargin, context), other != target {
            state = .idle
            return nil
        }

        // (e) A short gap (at most maxGap): the dwell clock keeps running, but only a supporting sample can fire.
        return decision(
            .dwelling(display: target, progress: progress(since: start, at: t)), reason: .dwelling, classification)
    }

    // MARK: - Step 5

    private mutating func processIdle(
        at t: Double,
        _ classification: PoseClassification,
        _ context: SwitchContext
    ) -> SwitchDecision {
        if let reason = holdReason(classification, context) {
            return decision(.idle, reason: reason, classification)
        }
        // No hold reason means a display with enough margin, so `best` is set; the guard only avoids a force
        // unwrap.
        guard let best = classification.best else {
            return decision(.idle, reason: .noFace, classification)
        }
        if isDwellComplete(after: 0) {  // dwell <= 0 (within ε): nothing to wait for
            return fire(best, at: t, classification)
        }
        state = .dwelling(display: best, start: t, lastSupport: t)
        return decision(.dwelling(display: best, progress: 0), reason: .dwelling, classification)
    }

    /// Why an idle decider does not start a dwell on this sample, in the contract's order, or `nil` when it
    /// would (the contract's `holdReason(c)` with its "no reason applies" case made explicit).
    private func holdReason(_ classification: PoseClassification, _ context: SwitchContext) -> SwitchHoldReason? {
        switch classification.kind {
        case .noFace:
            return .noFace
        case .elsewhere:
            return .elsewhere
        case .display:
            guard let best = classification.best else { return .noFace }
            if !isTarget(best, context) { return .notATarget }
            if best == context.focusedDisplay { return .alreadyFocused }
            if classification.margin < settings.enterMargin { return .uncertain }
            return nil
        }
    }

    // MARK: - Helpers

    /// `inTargets(D)` from the contract: `targets == nil` means every calibrated display.
    private func isTarget(_ display: DisplayID, _ context: SwitchContext) -> Bool {
        context.targets?.contains(display) ?? true
    }

    /// The best display when `eligible(c, m)` from the contract holds, else `nil`.
    private func eligibleDisplay(
        _ classification: PoseClassification,
        margin: Double,
        _ context: SwitchContext
    ) -> DisplayID? {
        guard classification.kind == .display, classification.margin >= margin, let best = classification.best,
            isTarget(best, context)
        else {
            return nil
        }
        return best
    }

    /// A dwell is complete when `elapsed >= dwell - ε`.
    private func isDwellComplete(after elapsed: Double) -> Bool {
        elapsed >= settings.dwell - Self.timeTolerance
    }

    private func progress(since start: Double, at t: Double) -> Double {
        guard settings.dwell > 0 else { return 1 }
        return min(1, (t - start) / settings.dwell)
    }

    /// Completes a dwell: enters the cooldown and tells the caller to switch to `target`.
    private mutating func fire(
        _ target: DisplayID, at t: Double, _ classification: PoseClassification
    )
        -> SwitchDecision
    {
        let until = t + settings.cooldown
        state = .coolingDown(until: until)
        log.debug("switch fired; cooldown until \(until, privacy: .public)")
        return SwitchDecision(
            switchTo: target, phase: .coolingDown(until: until), reason: nil, classification: classification)
    }

    private func decision(
        _ phase: SwitchPhase,
        reason: SwitchHoldReason,
        _ classification: PoseClassification
    ) -> SwitchDecision {
        SwitchDecision(switchTo: nil, phase: phase, reason: reason, classification: classification)
    }
}
