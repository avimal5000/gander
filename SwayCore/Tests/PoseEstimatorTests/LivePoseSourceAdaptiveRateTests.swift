import Foundation
import SwayModels
import Testing
import os

@testable import PoseEstimator

/// `LivePoseSource` with the adaptive frame rate (CONTRACT 6.2.1), against a fake frame source and a fake
/// estimator. Frames are made up at 100 s + index / fps, and the power state is injected, so nothing here touches a
/// camera, Vision, or the machine's real power settings.
@Suite("LivePoseSource adaptive frame rate")
struct LivePoseSourceAdaptiveRateTests {
    private let start: TimeInterval = 100

    private func drain(_ stream: AsyncStream<PoseSourceEvent>) async -> [PoseSourceEvent] {
        var events: [PoseSourceEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    /// A source whose power state is the value of `constrained` (a test changes it to simulate Low Power Mode).
    private func makeSource(
        _ frames: FakeFrameSource,
        _ estimator: FakePoseEstimator,
        constrained: OSAllocatedUnfairLock<Bool> = OSAllocatedUnfairLock(initialState: false)
    ) -> LivePoseSource {
        LivePoseSource(
            frameSource: frames, estimator: estimator, isPowerConstrained: { constrained.withLock { $0 } })
    }

    private func time(_ index: Int, fps: Double = 15) -> TimeInterval { start + Double(index) / fps }

    /// Emits the frames `indices` of a stream at `fps`.
    private func emit(_ frames: FakeFrameSource, _ indices: Range<Int>, fps: Double = 15) {
        for index in indices { frames.emitFrame(timestamp: time(index, fps: fps)) }
    }

    /// The frame indices (at `fps`) of the frames the estimator saw.
    private func estimatedIndices(_ estimator: FakePoseEstimator, fps: Double = 15) -> [Int] {
        estimator.estimatedTimestamps.map { Int((($0 - start) * fps).rounded()) }
    }

    private func gaps(_ indices: [Int]) -> [Int] {
        zip(indices, indices.dropFirst()).map { $1 - $0 }
    }

    // MARK: The cap and the default

    @Test func aThirtyFpsDeviceIsProcessedAtFifteenFps() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        let stream = try await source.start(PoseSourceConfiguration())
        emit(frames, 0..<60, fps: 30)  // 2 s at 30 fps
        await source.stop()

        let seen = estimatedIndices(estimator, fps: 30)
        #expect(seen == Array(stride(from: 0, to: 60, by: 2)))
        // Dropped frames yield nothing: one sample per estimated frame, plus the statuses.
        let events = await drain(stream)
        let samples = events.compactMap { event -> PoseSample? in
            if case .sample(let sample) = event { sample } else { nil }
        }
        #expect(samples.count == 30)
        #expect(samples.map(\.timestamp) == estimator.estimatedTimestamps)
        #expect(events.count == 32)
    }

    @Test func aFifteenFpsDeviceIsNotThinned() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        _ = try await source.start(PoseSourceConfiguration())
        emit(frames, 0..<150)
        await source.stop()

        #expect(estimatedIndices(estimator) == Array(0..<150))
    }

    @Test func theDemandAfterStartIsFullSoAbsentFacesAreNotThrottled() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator(hasFace: { _ in false })
        let source = makeSource(frames, estimator, constrained: OSAllocatedUnfairLock(initialState: true))

        _ = try await source.start(PoseSourceConfiguration())
        emit(frames, 0..<150)  // 10 s without a face, even power constrained
        await source.stop()

        #expect(estimatedIndices(estimator) == Array(0..<150))
    }

    // MARK: Adaptive

    @Test func adaptiveDropsToFiveFpsAfterTwoSecondsWithoutAFaceAndReturnsAtFullRateOnTheFirstFace() async throws {
        let frames = FakeFrameSource()
        // Face for the first 5 s, none for the next 10 s, then the face is back (15 fps, 20 s in all).
        let estimator = FakePoseEstimator(hasFace: { $0 < 105 || $0 >= 115 })
        let source = makeSource(frames, estimator)

        let stream = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<300)
        await source.stop()

        let seen = estimatedIndices(estimator)
        // Every frame while a face is there, and for the 2 s after it left (the last face frame is 74).
        #expect(Array(0...102).allSatisfy(seen.contains))
        // Then one frame per 0.2 s (every third) until the face is back.
        let throttled = seen.filter { $0 >= 108 && $0 < 225 }
        #expect(throttled.count > 30)
        #expect(Set(gaps(throttled)) == [3])
        // The first processed frame after the face returned at 225 has the face, and from then on every frame is
        // processed again.
        let back = seen.filter { $0 >= 225 }
        let firstBack = try #require(back.first)
        #expect((225...227).contains(firstBack))
        #expect(back == Array(firstBack..<300))
        // In all, the 10 s without a face cost about 80 fewer estimates.
        #expect(seen.count < 300 - 70)

        // One sample per estimated frame. The stream keeps only the newest 64 events, so compare the tail.
        let events = await drain(stream)
        let samples = events.compactMap { event -> PoseSample? in
            if case .sample(let sample) = event { sample } else { nil }
        }
        #expect(samples.count > 40)
        #expect(samples.map(\.timestamp) == Array(estimator.estimatedTimestamps.suffix(samples.count)))
    }

    @Test func glancesAwayShorterThanTwoSecondsNeverThinTheStream() async throws {
        let frames = FakeFrameSource()
        // The face drops out for 1.5 s (22 frames) every 4 s.
        let estimator = FakePoseEstimator(hasFace: { ($0 - 100).truncatingRemainder(dividingBy: 4) >= 1.5 })
        let source = makeSource(frames, estimator)

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<300)
        await source.stop()

        #expect(estimatedIndices(estimator) == Array(0..<300))
    }

    @Test func aStartCountsAsAFaceSoAdaptiveBeginsAtFullRate() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator(hasFace: { _ in false })
        let source = makeSource(frames, estimator)

        let stream = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<60)  // 4 s, never a face
        await source.stop()

        let seen = estimatedIndices(estimator)
        #expect(Array(0..<30).allSatisfy(seen.contains))  // the first 2 s: every frame
        #expect(Set(gaps(seen.filter { $0 >= 33 })) == [3])  // then every third

        // Each estimated frame is a sample without a pose, and a dropped frame is nothing at all.
        let events = await drain(stream)
        let samples = events.compactMap { event -> PoseSample? in
            if case .sample(let sample) = event { sample } else { nil }
        }
        #expect(samples.map(\.timestamp) == estimator.estimatedTimestamps)
        #expect(samples.allSatisfy { $0.pose == nil })
    }

    // MARK: Reduced and demand changes

    @Test func reducedLowersTheRateEvenWithAFaceAndFullRestoresIt() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.reduced)
        emit(frames, 0..<60)
        source.setDemand(.full)
        emit(frames, 60..<90)
        source.setDemand(.adaptive)
        emit(frames, 90..<120)  // the face is there, so adaptive is full rate
        source.setDemand(.reduced)
        emit(frames, 120..<150)
        await source.stop()

        let seen = estimatedIndices(estimator)
        #expect(seen.filter { $0 < 60 } == Array(stride(from: 0, to: 60, by: 3)))
        // The demand change takes effect on the next frame: no frame of the full-rate stretch is dropped.
        #expect(Array(60..<120).allSatisfy(seen.contains))
        #expect(Set(gaps(seen.filter { $0 >= 120 })) == [3])
    }

    @Test func reducedYieldsOneSamplePerEstimatedFrameAndNothingForDroppedOnes() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        let stream = try await source.start(PoseSourceConfiguration())
        source.setDemand(.reduced)
        emit(frames, 0..<30)
        await source.stop()

        let events = await drain(stream)
        var expected: [PoseSourceEvent] = [.status(.starting)]
        for index in stride(from: 0, to: 30, by: 3) {
            expected.append(.sample(PoseSample(timestamp: time(index), pose: FakePoseEstimator.pose(at: time(index)))))
        }
        expected.append(.status(.stopped))
        #expect(events == expected)
        #expect(estimator.estimatedTimestamps.count == 10)
    }

    @Test func setDemandBeforeStartIsForgottenByStart() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        source.setDemand(.reduced)
        _ = try await source.start(PoseSourceConfiguration())
        emit(frames, 0..<30)
        await source.stop()

        #expect(estimatedIndices(estimator) == Array(0..<30))
    }

    @Test func startResetsTheRateAndTheDemand() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator)

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.reduced)
        emit(frames, 0..<30)
        let before = estimator.estimatedTimestamps.count
        #expect(before == 10)

        // The second run starts at full rate, and its first frame is processed even though it is earlier in time and
        // only a moment after the last one.
        _ = try await source.start(PoseSourceConfiguration())
        let secondRun: [TimeInterval] = [50, 50 + 1.0 / 15, 50 + 2.0 / 15]
        for timestamp in secondRun { frames.emitFrame(timestamp: timestamp) }
        await source.stop()

        #expect(Array(estimator.estimatedTimestamps.dropFirst(before)) == secondRun)
    }

    @Test func startForgetsHowLongTheFaceHasBeenAbsent() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator(hasFace: { _ in false })
        let source = makeSource(frames, estimator)

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<150)  // throttled well before the end
        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        let before = estimator.estimatedTimestamps.count
        emit(frames, 150..<180)  // 2 s in a new run: the start counts as a face
        await source.stop()

        #expect(estimator.estimatedTimestamps.count - before == 30)
    }

    // MARK: Power

    @Test func powerConstrainedAdaptiveRunsAtTenFpsWithAFace() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator, constrained: OSAllocatedUnfairLock(initialState: true))

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<45)
        await source.stop()

        // 1/10 s on a 15 fps device is exactly 10 fps: gaps alternate two and one frames (frames 0, 2, 3, 5, 6...),
        // 30 estimates in 3 s.
        let seen = estimatedIndices(estimator)
        #expect(seen == Array(0..<45).filter { $0 % 3 != 1 })
        #expect(seen.count == 30)
        // One missed sample leaves at most 3 frames (0.2 s), under the decider's 0.25 s `maxGap`.
        for (first, second) in zip(gaps(seen), gaps(seen).dropFirst()) {
            #expect(first + second <= 3)
        }
    }

    @Test func powerConstrainedAdaptiveRunsAtTwoFpsWithoutAFace() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator(hasFace: { $0 < 100.5 })
        let source = makeSource(frames, estimator, constrained: OSAllocatedUnfairLock(initialState: true))

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<300)
        await source.stop()

        // 1/2 s on a 15 fps device is 7.5 frames: gaps alternate 7 and 8, so exactly 2 fps.
        let throttled = estimatedIndices(estimator).filter { $0 >= 45 }
        #expect(throttled.count > 25)
        #expect(Set(gaps(throttled)) == [7, 8])
        #expect(zip(gaps(throttled), gaps(throttled).dropFirst()).allSatisfy { $0 + $1 == 15 })
    }

    @Test func powerConstrainedReducedRunsAtTwoFps() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator, constrained: OSAllocatedUnfairLock(initialState: true))

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.reduced)
        emit(frames, 0..<120)
        await source.stop()

        let seen = estimatedIndices(estimator)
        #expect(Set(gaps(seen)) == [7, 8])
        #expect(zip(gaps(seen), gaps(seen).dropFirst()).allSatisfy { $0 + $1 == 15 })
        #expect(seen.count == 16)  // the first frame, then one per 0.5 s: frames 0, 8, 15, 23... 113 of 0..<120
    }

    @Test func fullDemandIsNotLoweredByAPowerConstraint() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = makeSource(frames, estimator, constrained: OSAllocatedUnfairLock(initialState: true))

        _ = try await source.start(PoseSourceConfiguration())
        emit(frames, 0..<60)
        await source.stop()

        #expect(estimatedIndices(estimator) == Array(0..<60))
    }

    @Test func aPowerStateChangeTakesEffectWithinASecondOfFrameTime() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let constrained = OSAllocatedUnfairLock(initialState: false)
        let source = makeSource(frames, estimator, constrained: constrained)

        _ = try await source.start(PoseSourceConfiguration())
        source.setDemand(.adaptive)
        emit(frames, 0..<45)
        constrained.withLock { $0 = true }
        emit(frames, 45..<120)
        constrained.withLock { $0 = false }
        emit(frames, 120..<180)
        await source.stop()

        let seen = estimatedIndices(estimator)
        #expect(Array(0..<45).allSatisfy(seen.contains))
        // Constrained from 45 on, noticed within 15 frames (one second): exactly 10 fps, 40 of the 60 frames. Lifted
        // again the same way.
        let constrainedStretch = seen.filter { $0 >= 60 && $0 < 120 }
        #expect(constrainedStretch.count == 40)
        #expect(Set(gaps(constrainedStretch)) == [1, 2])
        #expect(Array(135..<180).allSatisfy(seen.contains))
    }

    @Test("The power state is read at most once per second of frame time, never per frame", arguments: [15.0, 30.0])
    func powerStateIsPolledAtMostOncePerSecond(fps: Double) async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let source = LivePoseSource(
            frameSource: frames, estimator: estimator,
            isPowerConstrained: {
                reads.withLock { $0 += 1 }
                return false
            })

        _ = try await source.start(PoseSourceConfiguration())
        // Nothing is read before the first frame.
        #expect(reads.withLock { $0 } == 0)
        frames.emitFrame(timestamp: start)
        #expect(reads.withLock { $0 } == 1)

        emit(frames, 1..<Int(10 * fps), fps: fps)  // the rest of 10 s of frame time
        await source.stop()

        // 10 s of frame time: at most 10 reads (the first frame, then one per second), not 150 or 300.
        let total = reads.withLock { $0 }
        #expect(total >= 9)
        #expect(total <= 10)
    }

    @Test func aStartPollsThePowerStateAgainOnItsFirstFrame() async throws {
        let frames = FakeFrameSource()
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let source = LivePoseSource(
            frameSource: frames, estimator: FakePoseEstimator(),
            isPowerConstrained: {
                reads.withLock { $0 += 1 }
                return false
            })

        _ = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: start)
        frames.emitFrame(timestamp: start + 0.1)
        #expect(reads.withLock { $0 } == 1)

        _ = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: start + 0.2)
        await source.stop()

        #expect(reads.withLock { $0 } == 2)
    }

    @Test func aFrameFromARetiredRunReadsNoPowerStateAndCountsNothing() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let source = LivePoseSource(
            frameSource: frames, estimator: estimator,
            isPowerConstrained: {
                reads.withLock { $0 += 1 }
                return false
            })

        _ = try await source.start(PoseSourceConfiguration())
        let staleHandler = try #require(frames.frameHandler)
        _ = try await source.start(PoseSourceConfiguration())
        staleHandler(CameraFrame(pixelBuffer: TestPixelBuffer.blank(), timestamp: start))
        #expect(reads.withLock { $0 } == 0)
        #expect(estimator.estimatedTimestamps.isEmpty)

        // The new run's first frame is still its first frame.
        frames.emitFrame(timestamp: start + 0.01)
        await source.stop()
        #expect(estimator.estimatedTimestamps == [start + 0.01])
        #expect(reads.withLock { $0 } == 1)
    }

    @Test(
        "The system power rule: Low Power Mode, or a serious or critical heat level",
        arguments: [
            (false, ProcessInfo.ThermalState.nominal, false), (false, .fair, false), (false, .serious, true),
            (false, .critical, true), (true, .nominal, true), (true, .serious, true),
        ])
    func systemPowerRule(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState, expected: Bool) {
        #expect(LivePoseSource.isConstrained(lowPowerMode: lowPowerMode, thermalState: thermalState) == expected)
    }
}
