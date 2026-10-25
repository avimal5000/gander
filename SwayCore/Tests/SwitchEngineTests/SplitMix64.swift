import Foundation

/// Deterministic pseudo-random generator (SplitMix64) with Gaussian sampling (Box-Muller), so synthetic
/// scenarios replay identically on every run. Test-target copy; the engine itself uses no randomness.
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

    /// Uniform sample in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Standard normal sample.
    mutating func nextGaussian() -> Double {
        if let spare = spareGaussian {
            spareGaussian = nil
            return spare
        }
        let u1 = 1.0 - nextUnit()
        let u2 = nextUnit()
        let radius = (-2.0 * log(u1)).squareRoot()
        spareGaussian = radius * sin(2.0 * Double.pi * u2)
        return radius * cos(2.0 * Double.pi * u2)
    }
}
