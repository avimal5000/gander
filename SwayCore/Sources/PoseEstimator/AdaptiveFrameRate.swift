import Foundation
import SwayModels

/// Decides which camera frames are worth running Vision on (SPEC D45). Vision face detection costs about the same
/// per call whatever the picture, so the only way to lower CPU is fewer calls per second.
///
/// The minimum interval between processed frames depends on the demand, whether the machine is power constrained
/// (Low Power Mode or a serious heat level), and whether a face has been seen in the last 2 s:
///
/// | Demand                                  | No power constraint | Power constrained |
/// |-----------------------------------------|---------------------|-------------------|
/// | `.full`                                 | 1/15 s              | 1/15 s            |
/// | `.adaptive`, face seen within 2 s       | 1/15 s              | 1/10 s            |
/// | `.adaptive`, no face for 2 s or more    | 1/5 s               | 1/2 s             |
/// | `.reduced`                              | 1/5 s               | 1/2 s             |
///
/// So no table row ever exceeds 15 fps, whatever rate the device delivers. While a face is present the rate is
/// 15 fps in every unconstrained case, which keeps the switch decider's dwell and gap rules exactly as they are.
///
/// A frame is processed when its time is at least `interval - jitterTolerance` after the last processed frame, so a
/// 15 fps device is not dropped by timing noise. The effective rate is therefore quantized to the device's frame
/// period: a 15 fps device gives every frame, every 3rd frame (5 fps), every 2nd frame when 1/10 s applies, and
/// every 8th frame when 1/2 s applies.
///
/// The type has no clock of its own. It works on frame timestamps in seconds, which only need to be comparable
/// with each other, so it is pure and tests drive it with made-up times.
struct AdaptiveFrameRate: Sendable, Equatable {
    /// The shortest interval ever used: the hard 15 fps cap.
    static let fullInterval: TimeInterval = 1.0 / 15
    /// With `.adaptive`, a face present, and a power constraint.
    static let constrainedActiveInterval: TimeInterval = 1.0 / 10
    /// With `.reduced`, or `.adaptive` and no face for `absenceThreshold`.
    static let idleInterval: TimeInterval = 1.0 / 5
    /// The same as `idleInterval` when power constrained.
    static let constrainedIdleInterval: TimeInterval = 1.0 / 2
    /// How long without a face before `.adaptive` drops to the idle interval.
    static let absenceThreshold: TimeInterval = 2
    /// Slack when comparing a frame gap with an interval, in seconds.
    static let jitterTolerance: TimeInterval = 0.004

    /// How much frame rate the app wants now.
    private(set) var demand: PoseDemand = .full
    /// Whether Low Power Mode or a serious heat level applies.
    private(set) var isPowerConstrained = false
    /// Time of the last frame that was processed; `nil` until the first one after a reset.
    private var lastProcessed: TimeInterval?
    /// Time of the last processed frame that had a face, or the first processed frame after a reset (a start counts
    /// as a face just seen); `nil` until that first frame.
    private var lastFaceSeen: TimeInterval?

    /// The minimum time between two processed frames, for a frame at time `t`.
    func minimumInterval(at t: TimeInterval) -> TimeInterval {
        switch demand {
        case .full:
            return Self.fullInterval
        case .adaptive:
            if hasSeenFace(within: Self.absenceThreshold, at: t) {
                return isPowerConstrained ? Self.constrainedActiveInterval : Self.fullInterval
            }
            return isPowerConstrained ? Self.constrainedIdleInterval : Self.idleInterval
        case .reduced:
            return isPowerConstrained ? Self.constrainedIdleInterval : Self.idleInterval
        }
    }

    /// Whether the frame at time `t` should be estimated. A `true` answer counts the frame as processed, so the
    /// caller must then estimate it and call `record(face:at:)`.
    ///
    /// The first frame after a reset is always processed. A frame earlier than the last processed one (the clock
    /// restarted) is processed and restarts the interval; it also pulls a face-seen time from the future back to
    /// `t`, so the rate cannot stay active for the length of the jump.
    mutating func shouldProcess(frameAt t: TimeInterval) -> Bool {
        if let last = lastProcessed {
            if t < last {
                if let seen = lastFaceSeen, seen > t { lastFaceSeen = t }
            } else if t - last < minimumInterval(at: t) - Self.jitterTolerance {
                return false
            }
        } else {
            lastFaceSeen = t
        }
        lastProcessed = t
        return true
    }

    /// Records the outcome of estimating the frame at time `t`. A frame with a face makes the very next frame
    /// eligible at the active interval; a frame without one changes nothing.
    mutating func record(face: Bool, at t: TimeInterval) {
        if face { lastFaceSeen = t }
    }

    /// Changes the demand. A higher rate applies from the next frame, because the interval is measured from the last
    /// processed frame and re-read on every frame.
    mutating func setDemand(_ demand: PoseDemand) {
        self.demand = demand
    }

    /// Records whether Low Power Mode or a serious heat level applies. Takes effect on the next frame.
    mutating func setPowerConstrained(_ isPowerConstrained: Bool) {
        self.isPowerConstrained = isPowerConstrained
    }

    /// Starts a new run: the next frame is processed, a face counts as just seen, and the demand is `.full`. The
    /// power state is kept, since it describes the machine and not the run.
    mutating func reset() {
        demand = .full
        lastProcessed = nil
        lastFaceSeen = nil
    }

    /// Whether a face was seen at most `window` seconds before `t`. Before any frame this is `true`.
    private func hasSeenFace(within window: TimeInterval, at t: TimeInterval) -> Bool {
        guard let seen = lastFaceSeen else { return true }
        return t - seen < window
    }
}
