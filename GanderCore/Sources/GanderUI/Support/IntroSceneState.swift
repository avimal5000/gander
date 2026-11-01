/// Where everything is at a moment in the intro's Fig. 1 loop (pure, so tests can pin the timeline).
///
/// Ten seconds: the focus rests on the left monitor, the head turns right, the focus ring slides across, "ship it" is
/// typed there, then it all eases back. The pointer never moves.
struct IntroSceneState: Equatable {
    /// Length of one loop, in seconds.
    static let duration: Double = 10
    /// The moment shown when Reduce Motion is on: the focus has arrived and the words are typed.
    static let stillTime: Double = 6.5
    /// What gets typed.
    static let typedText = "ship it"

    /// Head turn, 0 facing the screens to 1 turned right.
    var turn: Double
    /// Focus ring position, 0 on the left monitor to 1 on the right one.
    var ring: Double
    /// Opacity of the typed text, 0 to 1.
    var typedOpacity: Double
    /// How many characters of `typedText` show.
    var typedCount: Int

    init(at time: Double) {
        let t = time.truncatingRemainder(dividingBy: Self.duration)
        let t0 = t < 0 ? t + Self.duration : t
        turn = Self.ramp(t0, 1.8, 2.8) - Self.ramp(t0, 8.0, 9.0)
        ring = Self.ramp(t0, 3.0, 4.0) - Self.ramp(t0, 8.4, 9.4)
        typedCount = Int((Self.ramp(t0, 4.3, 6.3) * Double(Self.typedText.count)).rounded(.down))
        typedOpacity = typedCount == 0 ? 0 : 1 - Self.ramp(t0, 9.0, 9.6)
    }

    /// 0 before `from`, 1 after `to`, eased between.
    private static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double {
        let x = min(max((t - from) / (to - from), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
