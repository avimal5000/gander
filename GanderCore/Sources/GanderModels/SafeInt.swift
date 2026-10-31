import CoreGraphics
import Foundation

/// Conversions from floating point that never trap. `Int(x)` crashes on NaN, infinity and values beyond the `Int`
/// range, and values read from a trace file or stored settings are not trusted.
extension Int {
    /// Largest magnitude `init(clamping:)` returns for a finite value. Well inside the `Int` range, so sums of a few
    /// such values still cannot overflow.
    public static let safeDoubleLimit: Double = 1e15

    /// `value` rounded to the nearest integer and clamped to plus or minus `safeDoubleLimit`. NaN becomes 0.
    public init(clamping value: Double) {
        guard value.isFinite else {
            self = value.isNaN ? 0 : (value > 0 ? Int(Self.safeDoubleLimit) : -Int(Self.safeDoubleLimit))
            return
        }
        let limit = Self.safeDoubleLimit
        self = Int(Swift.min(Swift.max(value.rounded(), -limit), limit))
    }

    /// Same as `init(clamping: Double)` for a `CGFloat`.
    public init(clamping value: CGFloat) {
        self.init(clamping: Double(value))
    }
}
