import Foundation

/// A deterministic pseudo-random generator (SplitMix64) with uniform and Gaussian (Box–Muller) sampling.
///
/// Used instead of `SystemRandomNumberGenerator` so synthetic traces are reproducible from a seed.
/// Only integer arithmetic is involved in `next()`, so the raw stream is identical on every platform.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    private var spareGaussian: Double?

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform sample in [0, 1) with 53 bits of precision.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform index in 0..<bound (`bound` must be positive).
    mutating func nextIndex(below bound: Int) -> Int {
        min(bound - 1, Int(nextUnit() * Double(bound)))
    }

    /// Standard normal sample N(0, 1) via the Box–Muller transform. Each transform yields two samples; the
    /// second one is returned by the next call.
    mutating func nextGaussian() -> Double {
        if let spare = spareGaussian {
            spareGaussian = nil
            return spare
        }
        let u1 = 1.0 - nextUnit()  // in (0, 1], so the logarithm is finite
        let u2 = nextUnit()
        let radius = (-2.0 * log(u1)).squareRoot()
        let angle = 2.0 * Double.pi * u2
        spareGaussian = radius * sin(angle)
        return radius * cos(angle)
    }

    /// `count` distinct indices from 0..<total chosen uniformly (partial Fisher–Yates shuffle).
    mutating func pickDistinctIndices(count: Int, from total: Int) -> Set<Int> {
        let wanted = min(max(count, 0), max(total, 0))
        guard wanted > 0 else { return [] }
        var indices = Array(0..<total)
        for position in 0..<wanted {
            let other = position + nextIndex(below: total - position)
            indices.swapAt(position, other)
        }
        return Set(indices[0..<wanted])
    }
}
