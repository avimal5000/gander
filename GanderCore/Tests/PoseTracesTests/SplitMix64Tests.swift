import Testing

@testable import PoseTraces

@Suite struct SplitMix64Tests {
    @Test func matchesPublishedReferenceStreamForSeedZero() {
        var random = SplitMix64(seed: 0)
        let stream = (0..<3).map { _ in random.next() }
        #expect(stream == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F])
    }

    @Test func sameSeedGivesSameStreamAndDifferentSeedsDiffer() {
        var first = SplitMix64(seed: 99)
        var second = SplitMix64(seed: 99)
        var other = SplitMix64(seed: 100)
        let a = (0..<10).map { _ in first.next() }
        let b = (0..<10).map { _ in second.next() }
        let c = (0..<10).map { _ in other.next() }
        #expect(a == b)
        #expect(a != c)
    }

    @Test func unitSamplesStayInHalfOpenUnitInterval() {
        var random = SplitMix64(seed: 5)
        for _ in 0..<10_000 {
            let value = random.nextUnit()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test func gaussianSamplesHaveZeroMeanAndUnitSpread() {
        var random = SplitMix64(seed: 2024)
        let count = 40_000
        let samples = (0..<count).map { _ in random.nextGaussian() }
        let mean = samples.reduce(0, +) / Double(count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count - 1)
        #expect(abs(mean) < 0.03)
        #expect(abs(variance - 1) < 0.05)
        #expect(samples.allSatisfy { $0.isFinite })
    }

    @Test func distinctIndexPickingIsUniqueInRangeAndDeterministic() {
        var first = SplitMix64(seed: 7)
        var second = SplitMix64(seed: 7)
        let picked = first.pickDistinctIndices(count: 12, from: 60)
        #expect(picked.count == 12)
        #expect(picked.allSatisfy { (0..<60).contains($0) })
        #expect(picked == second.pickDistinctIndices(count: 12, from: 60))

        var third = SplitMix64(seed: 7)
        #expect(third.pickDistinctIndices(count: 100, from: 10).count == 10)
        #expect(third.pickDistinctIndices(count: 0, from: 10).isEmpty)
        #expect(third.pickDistinctIndices(count: 3, from: 0).isEmpty)
    }
}
