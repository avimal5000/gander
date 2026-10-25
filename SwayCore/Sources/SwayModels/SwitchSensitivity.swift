import Foundation

/// The switching settings the user can change (SPEC F21): how long to hold a look, and how sure Sway must be. The
/// other `SwitchSettings` fields keep their defaults.
public struct SwitchSensitivity: Sendable, Equatable, Codable {
    /// Allowed dwell, in seconds.
    public static let dwellRange: ClosedRange<Double> = 0.2...1.5
    /// Enter margins from "Relaxed" (index 0) to "Strict". The stay margin is always half the enter margin, as in the
    /// defaults.
    public static let confidenceMargins: [Double] = [0.15, 0.225, 0.30, 0.375, 0.45]
    /// The defaults: exactly `SwitchSettings.default`.
    public static let `default` = SwitchSensitivity(dwell: 0.40, confidenceLevel: 2)

    /// Seconds a look must be held before focus switches.
    public var dwell: Double
    /// Index into `confidenceMargins`.
    public var confidenceLevel: Int

    /// Clamps both values into their allowed ranges.
    public init(dwell: Double, confidenceLevel: Int) {
        self.dwell = min(max(dwell, Self.dwellRange.lowerBound), Self.dwellRange.upperBound)
        self.confidenceLevel = min(max(confidenceLevel, 0), Self.confidenceMargins.count - 1)
    }

    /// `base` with this dwell and margins.
    public func switchSettings(base: SwitchSettings = .default) -> SwitchSettings {
        let clamped = SwitchSensitivity(dwell: dwell, confidenceLevel: confidenceLevel)
        var settings = base
        settings.dwell = clamped.dwell
        settings.enterMargin = Self.confidenceMargins[clamped.confidenceLevel]
        settings.stayMargin = settings.enterMargin / 2
        return settings
    }
}
