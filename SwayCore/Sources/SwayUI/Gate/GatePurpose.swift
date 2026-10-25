/// What a gate run is for. The run itself (steps over the displays, overlays, camera hold) is the same machinery;
/// the purpose picks its timing, what happens to the trace, and where messages go.
enum GatePurpose: Equatable, Sendable {
    /// The Head-Pose Gate Test window: user-chosen rounds and hold time, landmarks on, and a report.
    case gateTest
    /// The Setup window's guided calibration (SPEC D30): two rounds, 2.5 s holds, Vision angles only, and a saved
    /// calibration with a verdict.
    case calibration

    /// The run's name inside a sentence.
    var noun: String {
        switch self {
        case .gateTest: "gate test"
        case .calibration: "calibration"
        }
    }

    /// What to tell the user to do after a run ended early.
    var tryAgain: String {
        switch self {
        case .gateTest: "Run the test again."
        case .calibration: "Calibrate again."
        }
    }
}
