import Foundation

/// The switching settings the user can change (SPEC F21, F35): how long to hold a look, how long to pause after a
/// switch, and how sure Gander must be. The other `SwitchSettings` fields keep their defaults.
public struct SwitchSensitivity: Sendable, Equatable, Codable {
    /// Allowed dwell, in seconds.
    public static let dwellRange: ClosedRange<Double> = 0.05...1.5
    /// Allowed cooldown, in seconds.
    public static let cooldownRange: ClosedRange<Double> = 0.2...1.5
    /// Enter margins from "Relaxed" (index 0) to "Strict". The stay margin is always half the enter margin, as in the
    /// defaults.
    public static let confidenceMargins: [Double] = [0.15, 0.225, 0.30, 0.375, 0.45]
    /// The defaults: exactly `SwitchSettings.default`.
    public static let `default` = SwitchSensitivity(dwell: 0.40, cooldown: 0.75, confidenceLevel: 2)
    /// The "Instant" timing (SPEC D49): a short hold and a short pause, with the default confidence. Apply it to the
    /// user's own settings with `applyingInstantTiming()`, which leaves their confidence alone.
    public static let instant = SwitchSensitivity(dwell: 0.10, cooldown: 0.30, confidenceLevel: 2)

    /// Seconds a look must be held before focus switches.
    public var dwell: Double
    /// Seconds after a switch during which no new look starts counting.
    public var cooldown: Double
    /// Index into `confidenceMargins`.
    public var confidenceLevel: Int

    /// Clamps all three values into their allowed ranges.
    public init(dwell: Double, cooldown: Double, confidenceLevel: Int) {
        self.dwell = Self.clamp(dwell, to: Self.dwellRange, fallback: 0.40)
        self.cooldown = Self.clamp(cooldown, to: Self.cooldownRange, fallback: 0.75)
        self.confidenceLevel = min(max(confidenceLevel, 0), Self.confidenceMargins.count - 1)
    }

    /// Settings saved before the pause was adjustable: the default cooldown (0.75 s).
    public init(dwell: Double, confidenceLevel: Int) {
        self.init(dwell: dwell, cooldown: Self.default.cooldown, confidenceLevel: confidenceLevel)
    }

    /// Reads settings saved by any version. A missing `cooldown` is the default, and out-of-range values are clamped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dwell: try container.decode(Double.self, forKey: .dwell),
            cooldown: try container.decodeIfPresent(Double.self, forKey: .cooldown) ?? Self.default.cooldown,
            confidenceLevel: try container.decode(Int.self, forKey: .confidenceLevel))
    }

    /// Always writes all three values.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dwell, forKey: .dwell)
        try container.encode(cooldown, forKey: .cooldown)
        try container.encode(confidenceLevel, forKey: .confidenceLevel)
    }

    /// These settings with the hold time and pause of `instant`, and the same confidence.
    public func applyingInstantTiming() -> SwitchSensitivity {
        SwitchSensitivity(dwell: Self.instant.dwell, cooldown: Self.instant.cooldown, confidenceLevel: confidenceLevel)
    }

    /// `base` with this dwell, cooldown, and margins.
    public func switchSettings(base: SwitchSettings = .default) -> SwitchSettings {
        let clamped = SwitchSensitivity(dwell: dwell, cooldown: cooldown, confidenceLevel: confidenceLevel)
        var settings = base
        settings.dwell = clamped.dwell
        settings.cooldown = clamped.cooldown
        settings.enterMargin = Self.confidenceMargins[clamped.confidenceLevel]
        settings.stayMargin = settings.enterMargin / 2
        return settings
    }

    private enum CodingKeys: String, CodingKey {
        case dwell, cooldown, confidenceLevel
    }

    /// Clamps into `range`. A non-finite value (NaN, infinity) becomes `fallback`, which is itself in range.
    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
