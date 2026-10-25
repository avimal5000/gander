import Foundation

/// User-chosen settings for one guided gate test (SPEC F7).
struct GateTestConfiguration: Equatable, Sendable {
    /// Allowed number of rounds.
    static let roundsRange = 1...3
    /// Allowed hold time per display, in seconds.
    static let holdRange: ClosedRange<TimeInterval> = 3...10
    static let defaultRounds = 2
    static let defaultHoldDuration: TimeInterval = 5
    /// Time the user gets to move their gaze before samples count.
    static let settleDuration: TimeInterval = 1.5

    /// The guided calibration's settings (SPEC D30): two rounds over the displays, each look 1.5 s of settling and
    /// 2.5 s of hold. Its hold is shorter than the gate test window allows.
    static let calibration = GateTestConfiguration(rounds: 2, holdDuration: 2.5, shortestHold: 2.5)

    /// Passes through each display in layout order.
    var rounds: Int
    /// Seconds of recorded samples per display and round.
    var holdDuration: TimeInterval
    /// The shortest hold this configuration may have (the gate test's range starts at 3 s).
    private let shortestHold: TimeInterval

    init(rounds: Int = Self.defaultRounds, holdDuration: TimeInterval = Self.defaultHoldDuration) {
        self.init(rounds: rounds, holdDuration: holdDuration, shortestHold: Self.holdRange.lowerBound)
    }

    private init(rounds: Int, holdDuration: TimeInterval, shortestHold: TimeInterval) {
        self.rounds = min(max(rounds, Self.roundsRange.lowerBound), Self.roundsRange.upperBound)
        self.shortestHold = shortestHold
        self.holdDuration = min(max(holdDuration, shortestHold), Self.holdRange.upperBound)
    }

    /// The same settings forced into the allowed ranges.
    var clamped: GateTestConfiguration {
        GateTestConfiguration(rounds: rounds, holdDuration: holdDuration, shortestHold: shortestHold)
    }

    /// Rough total running time for `displayCount` displays, settle phases included.
    func estimatedDuration(displayCount: Int) -> TimeInterval {
        let clamped = self.clamped
        return Double(clamped.rounds * displayCount) * (Self.settleDuration + clamped.holdDuration)
    }
}
