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

    /// Passes through each display in layout order.
    var rounds: Int
    /// Seconds of recorded samples per display and round.
    var holdDuration: TimeInterval

    init(rounds: Int = Self.defaultRounds, holdDuration: TimeInterval = Self.defaultHoldDuration) {
        self.rounds = min(max(rounds, Self.roundsRange.lowerBound), Self.roundsRange.upperBound)
        self.holdDuration = min(max(holdDuration, Self.holdRange.lowerBound), Self.holdRange.upperBound)
    }

    /// The same settings forced into the allowed ranges.
    var clamped: GateTestConfiguration { GateTestConfiguration(rounds: rounds, holdDuration: holdDuration) }

    /// Rough total running time for `displayCount` displays, settle phases included.
    func estimatedDuration(displayCount: Int) -> TimeInterval {
        let clamped = self.clamped
        return Double(clamped.rounds * displayCount) * (Self.settleDuration + clamped.holdDuration)
    }
}
