import Testing

struct SplitMix64Tests {
    @Test func sameSeedGivesTheSameStream() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        let a = (0..<20).map { _ in first.nextGaussian() }
        let b = (0..<20).map { _ in second.nextGaussian() }
        #expect(a == b)
    }

    @Test func differentSeedsDiffer() {
        var first = SplitMix64(seed: 1)
        var second = SplitMix64(seed: 2)
        #expect(first.next() != second.next())
    }

    @Test func gaussianHasRoughlyUnitMomentsAndUnitIntervalIsBounded() {
        var rng = SplitMix64(seed: 7)
        let values = (0..<20_000).map { _ in rng.nextGaussian() }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        #expect(abs(mean) < 0.05)
        #expect(abs(variance - 1) < 0.05)
        let units = (0..<1000).map { _ in rng.nextUnit() }
        #expect(units.allSatisfy { $0 >= 0 && $0 < 1 })
    }
}
