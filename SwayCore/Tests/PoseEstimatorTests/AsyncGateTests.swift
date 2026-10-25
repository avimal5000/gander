import Foundation
import Testing
import os

@testable import PoseEstimator

@Suite("AsyncGate")
struct AsyncGateTests {
    private struct Occupancy {
        var current = 0
        var maximum = 0
        var entries = 0
    }

    @Test func holdersNeverOverlap() async {
        let gate = AsyncGate()
        let occupancy = OSAllocatedUnfairLock(initialState: Occupancy())

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.acquire()
                    occupancy.withLock {
                        $0.current += 1
                        $0.maximum = max($0.maximum, $0.current)
                        $0.entries += 1
                    }
                    await Task.yield()
                    occupancy.withLock { $0.current -= 1 }
                    gate.release()
                }
            }
        }

        let result = occupancy.withLock { $0 }
        #expect(result.entries == 20)
        #expect(result.maximum == 1)
    }

    @Test func gateCanBeReacquiredAfterRelease() async {
        let gate = AsyncGate()
        await gate.acquire()
        gate.release()
        await gate.acquire()
        gate.release()
    }
}
