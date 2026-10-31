import CoreMedia
import GanderModels

/// A supported frame rate range in frames per second (a plain mirror of `AVFrameRateRange`).
struct FrameRateRange: Sendable, Equatable {
    var min: Double
    var max: Double
}

/// Pure frame-rate clamping (CONTRACT 6.1): the requested rate is moved into a range the device supports.
enum FrameRateClamper {
    /// Allowed slack when deciding whether a rate sits inside a range (floating point noise).
    static let tolerance = 1e-6

    /// Returns the frame rate to apply, or `nil` when no usable range is known (leave the device alone).
    ///
    /// - A non-finite or non-positive request is replaced by `GanderPolicy.defaultFrameRate`.
    /// - A rate inside any range is kept as requested.
    /// - Otherwise the nearest range boundary wins; ties go to the earlier range.
    /// - Ranges that are not finite, not positive, or inverted (`min > max`) are ignored.
    static func clampedFrameRate(requested: Double, ranges: [FrameRateRange]) -> Double? {
        let usable = ranges.filter { $0.min.isFinite && $0.max.isFinite && $0.min > 0 && $0.min <= $0.max }
        guard !usable.isEmpty else { return nil }

        let target = (requested.isFinite && requested > 0) ? requested : GanderPolicy.defaultFrameRate
        if usable.contains(where: { target >= $0.min - tolerance && target <= $0.max + tolerance }) {
            return target
        }

        var best = usable[0]
        var bestClamped = clamp(target, to: best)
        for range in usable.dropFirst() {
            let candidate = clamp(target, to: range)
            if abs(candidate - target) < abs(bestClamped - target) {
                best = range
                bestClamped = candidate
            }
        }
        return bestClamped
    }

    /// Frame duration (`1 / rate`) as an exact rational, for rates that are not a range boundary.
    ///
    /// The value is `1000 / (rate * 1000)`, so common rates such as 15 or 30 are exact. Callers prefer the
    /// device's own boundary durations when the rate equals a range limit.
    static func frameDuration(forRate rate: Double) -> CMTime {
        let timescale = Int32(clamping: Int((rate * 1000).rounded()))
        return CMTime(value: 1000, timescale: max(timescale, 1))
    }

    private static func clamp(_ value: Double, to range: FrameRateRange) -> Double {
        min(max(value, range.min), range.max)
    }
}
