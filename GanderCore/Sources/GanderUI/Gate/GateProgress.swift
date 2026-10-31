import Foundation
import GanderModels

/// A snapshot of a running gate test for the overlay and the gate window.
struct GateProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Counting down; samples are discarded.
        case settle
        /// Recording samples for the target display.
        case hold
    }

    var phase: Phase
    /// 1-based index of the current step out of `stepCount` (rounds x displays).
    var stepNumber: Int
    var stepCount: Int
    /// 1-based round out of `rounds`.
    var round: Int
    var rounds: Int
    /// 1-based position of the target in layout order, out of `displayCount`.
    var displayNumber: Int
    var displayCount: Int
    /// The display the user is asked to look at.
    var display: DisplayInfo
    /// Seconds spent in the current phase, clamped to `phaseDuration`.
    var phaseElapsed: TimeInterval
    var phaseDuration: TimeInterval
    /// Samples recorded so far in the current hold phase (0 while settling).
    var recordedSamples: Int
    /// How many of those had a face.
    var recordedFaces: Int

    /// Seconds left in the current phase.
    var remaining: TimeInterval { max(0, phaseDuration - phaseElapsed) }

    /// 0...1 progress through the current phase.
    var fraction: Double { phaseDuration > 0 ? min(1, max(0, phaseElapsed / phaseDuration)) : 1 }
}
