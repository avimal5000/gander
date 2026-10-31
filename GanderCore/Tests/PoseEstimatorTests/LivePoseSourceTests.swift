import Foundation
import GanderModels
import Testing
import os

@testable import PoseEstimator

@Suite("LivePoseSource")
struct LivePoseSourceTests {
    private let camera = CameraDevice(id: "fake-cam", name: "Fake Camera", isBuiltIn: true)

    /// Reads a finished stream to its end. Only call after `stop()` or another call that finishes the stream.
    private func drain(_ stream: AsyncStream<PoseSourceEvent>) async -> [PoseSourceEvent] {
        var events: [PoseSourceEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func sample(_ timestamp: TimeInterval) -> PoseSourceEvent {
        .sample(PoseSample(timestamp: timestamp, pose: FakePoseEstimator.pose(at: timestamp)))
    }

    @Test func eventsArriveInOrderStartingStatusesThenSamples() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration(cameraDeviceID: "abc", frameRate: 12))
        frames.emitStatus(.running(camera))
        frames.emitFrame(timestamp: 1)
        frames.emitFrame(timestamp: 2)
        frames.emitStatus(.interrupted("Camera disconnected"))
        await source.stop()

        let events = await drain(stream)
        #expect(
            events == [
                .status(.starting),
                .status(.running(camera)),
                sample(1),
                sample(2),
                .status(.interrupted("Camera disconnected")),
                .status(.stopped),
            ])
        #expect(frames.lastDeviceID == "abc")
        #expect(frames.lastFrameRate == 12)
        #expect(estimator.estimatedTimestamps == [1, 2])
    }

    @Test func frameWithoutFaceBecomesSampleWithNilPose() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: -1)
        await source.stop()

        let events = await drain(stream)
        #expect(events == [.status(.starting), .sample(PoseSample(timestamp: -1, pose: nil)), .status(.stopped)])
    }

    @Test func stopFinishesTheStreamAndEmitsStoppedOnce() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        await source.stop()
        await source.stop()

        let events = await drain(stream)
        #expect(events == [.status(.starting), .status(.stopped)])
        #expect(frames.stopCount >= 1)
    }

    @Test func stopWithoutStartIsHarmless() async {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        await source.stop()
        await source.stop()

        #expect(frames.startCount == 0)
    }

    @Test func frameSourceReportingStoppedItselfDoesNotDuplicateStopped() async throws {
        let frames = FakeFrameSource()
        frames.state.withLock { $0.emitsStoppedOnStop = true }
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        await source.stop()

        let events = await drain(stream)
        #expect(events == [.status(.starting), .status(.stopped)])
    }

    @Test func framesAfterStopAreIgnored() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        let staleHandler = try #require(frames.frameHandler)
        await source.stop()
        staleHandler(CameraFrame(pixelBuffer: TestPixelBuffer.blank(), timestamp: 5))

        #expect(estimator.estimatedTimestamps.isEmpty)
        let events = await drain(stream)
        #expect(events == [.status(.starting), .status(.stopped)])
    }

    @Test func secondStartFinishesTheFirstStream() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let first = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: 1)
        let second = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: 2)

        // The first stream is already finished, so draining it cannot hang.
        let firstEvents = await drain(first)
        #expect(firstEvents == [.status(.starting), sample(1), .status(.stopped)])
        #expect(frames.startCount == 2)
        #expect(frames.stopCount >= 1)

        await source.stop()
        let secondEvents = await drain(second)
        #expect(secondEvents == [.status(.starting), sample(2), .status(.stopped)])
    }

    @Test func staleHandlersFromAPreviousRunNeverReachTheNewStream() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        _ = try await source.start(PoseSourceConfiguration())
        let staleHandler = try #require(frames.frameHandler)
        let second = try await source.start(PoseSourceConfiguration())

        staleHandler(CameraFrame(pixelBuffer: TestPixelBuffer.blank(), timestamp: 99))
        frames.emitFrame(timestamp: 3)
        await source.stop()

        let events = await drain(second)
        #expect(events == [.status(.starting), sample(3), .status(.stopped)])
        #expect(estimator.estimatedTimestamps == [3])
    }

    @Test(arguments: [true, false])
    func includeLandmarksFromTheConfigurationReachesTheEstimator(includeLandmarks: Bool) async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration(includeLandmarks: includeLandmarks))
        frames.emitFrame(timestamp: 1)
        frames.emitFrame(timestamp: 2)
        await source.stop()
        _ = await drain(stream)

        #expect(estimator.receivedIncludeLandmarks == [includeLandmarks, includeLandmarks])
    }

    @Test func landmarksAreOffByDefault() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: 1)
        await source.stop()
        _ = await drain(stream)

        #expect(estimator.receivedIncludeLandmarks == [false])
    }

    @Test func aRestartWithADifferentIncludeLandmarksValueUsesTheNewOne() async throws {
        let frames = FakeFrameSource()
        let estimator = FakePoseEstimator()
        let source = LivePoseSource(frameSource: frames, estimator: estimator, isPowerConstrained: { false })

        let first = try await source.start(PoseSourceConfiguration(includeLandmarks: false))
        let firstHandler = try #require(frames.frameHandler)
        frames.emitFrame(timestamp: 1)
        let second = try await source.start(PoseSourceConfiguration(includeLandmarks: true))
        frames.emitFrame(timestamp: 2)
        // The first run's handler is retired, so it does not estimate with the old value either.
        firstHandler(CameraFrame(pixelBuffer: TestPixelBuffer.blank(), timestamp: 3))
        let third = try await source.start(PoseSourceConfiguration(includeLandmarks: false))
        frames.emitFrame(timestamp: 4)
        await source.stop()
        _ = await drain(first)
        _ = await drain(second)
        _ = await drain(third)

        #expect(estimator.estimatedTimestamps == [1, 2, 4])
        #expect(estimator.receivedIncludeLandmarks == [false, true, false])
    }

    @Test(arguments: [CameraAuthorization.notDetermined, .denied, .restricted])
    func unauthorizedStartThrowsAndNeverStartsTheFrameSource(authorization: CameraAuthorization) async {
        let frames = FakeFrameSource(authorization: authorization)
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        await #expect(throws: CameraError.notAuthorized) {
            _ = try await source.start(PoseSourceConfiguration())
        }
        #expect(frames.startCount == 0)
    }

    @Test func unauthorizedStartStillEndsThePreviousRun() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let first = try await source.start(PoseSourceConfiguration())
        frames.state.withLock { $0.authorization = .denied }
        await #expect(throws: CameraError.notAuthorized) {
            _ = try await source.start(PoseSourceConfiguration())
        }

        let events = await drain(first)
        #expect(events == [.status(.starting), .status(.stopped)])
        #expect(frames.startCount == 1)
    }

    @Test func consumerCancellationStopsTheFrameSource() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        let consumer = Task {
            for await _ in stream {}
        }
        consumer.cancel()
        await consumer.value

        let stopped = await waitUntil { frames.stopCount >= 1 }
        #expect(stopped)

        // The source is reusable afterwards.
        let again = try await source.start(PoseSourceConfiguration())
        await source.stop()
        let events = await drain(again)
        #expect(events == [.status(.starting), .status(.stopped)])
    }

    @Test func droppingTheStreamStopsTheFrameSource() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        do {
            let stream = try await source.start(PoseSourceConfiguration())
            _ = stream
        }

        let stopped = await waitUntil { frames.stopCount >= 1 }
        #expect(stopped)
    }

    @Test func cancellingAnOldStreamDoesNotStopTheNewRun() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let first = try await source.start(PoseSourceConfiguration())
        let second = try await source.start(PoseSourceConfiguration())
        let stopsBefore = frames.stopCount

        let consumer = Task {
            for await _ in first {}
        }
        consumer.cancel()
        await consumer.value
        // Give any (incorrect) stop triggered by the old stream's termination time to run.
        try await Task.sleep(for: .milliseconds(50))
        frames.emitFrame(timestamp: 4)

        #expect(frames.stopCount == stopsBefore)
        await source.stop()
        let events = await drain(second)
        #expect(events == [.status(.starting), sample(4), .status(.stopped)])
    }

    @Test func startFailureReportsFailedFinishesTheStreamAndRethrows() async {
        let frames = FakeFrameSource()
        frames.state.withLock { $0.startError = CameraError.deviceUnavailable("busy") }
        let observed = OSAllocatedUnfairLock<AsyncStream<PoseSourceEvent>?>(initialState: nil)
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })
        { stream in
            observed.withLock { $0 = stream }
        }

        await #expect(throws: CameraError.deviceUnavailable("busy")) {
            _ = try await source.start(PoseSourceConfiguration())
        }

        let stream = observed.withLock { $0 }
        if let stream {
            let events = await drain(stream)
            #expect(events == [.status(.starting), .status(.failed(.deviceUnavailable("busy")))])
        } else {
            Issue.record("The stream observer was not called")
        }
        #expect(frames.startCount == 1)
        #expect(frames.stopCount >= 1)
    }

    @Test func theCamerasOwnStartingAndRunningAreReportedOnceEach() async throws {
        // CameraCaptureService reports `.starting` then `.running` from inside `start`; our own `.starting` comes
        // first, so the camera's is an echo.
        let frames = FakeFrameSource()
        frames.state.withLock { $0.statusesDuringStart = [.starting, .running(camera)] }
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        frames.emitStatus(.running(camera))  // the watchdog's "first frame" report repeats `.running`
        frames.emitFrame(timestamp: 1)
        await source.stop()

        let events = await drain(stream)
        #expect(events == [.status(.starting), .status(.running(camera)), sample(1), .status(.stopped)])
    }

    @Test func aFrameSourceThatReportsFailedBeforeThrowingYieldsOneFailed() async {
        // CameraCaptureService reports `.starting`, then `.failed(error)` to the status handler, then throws it.
        let frames = FakeFrameSource()
        let error = CameraError.deviceUnavailable("FaceTime HD Camera did not start")
        frames.state.withLock {
            $0.startError = error
            $0.statusesDuringStart = [.starting, .failed(error)]
        }
        let observed = OSAllocatedUnfairLock<AsyncStream<PoseSourceEvent>?>(initialState: nil)
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })
        { stream in
            observed.withLock { $0 = stream }
        }

        await #expect(throws: error) {
            _ = try await source.start(PoseSourceConfiguration())
        }

        guard let stream = observed.withLock({ $0 }) else {
            Issue.record("The stream observer was not called")
            return
        }
        let events = await drain(stream)
        #expect(events == [.status(.starting), .status(.failed(error))])
        #expect(frames.stopCount >= 1)
    }

    @Test func changingStatusesAreAllReportedButImmediateRepeatsAreNot() async throws {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let stream = try await source.start(PoseSourceConfiguration())
        for status: CaptureStatus in [
            .running(camera), .interrupted("No frames"), .interrupted("No frames"), .running(camera),
            .suspended(.screenLocked), .suspended(.screenLocked), .starting, .running(camera),
        ] {
            frames.emitStatus(status)
        }
        await source.stop()

        let events = await drain(stream)
        #expect(
            events == [
                .status(.starting), .status(.running(camera)), .status(.interrupted("No frames")),
                .status(.running(camera)), .status(.suspended(.screenLocked)), .status(.starting),
                .status(.running(camera)), .status(.stopped),
            ])
    }

    @Test func aRestartedRunReportsStartingAgain() async throws {
        // Deduplication is per run: the new run's `.starting` is never swallowed by the old run's last status.
        let frames = FakeFrameSource()
        frames.state.withLock { $0.statusesDuringStart = [.starting] }
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        let first = try await source.start(PoseSourceConfiguration())
        let second = try await source.start(PoseSourceConfiguration())
        await source.stop()

        #expect(await drain(first) == [.status(.starting), .status(.stopped)])
        #expect(await drain(second) == [.status(.starting), .status(.stopped)])
    }

    @Test func nonCameraStartErrorsBecomeConfigurationFailed() async {
        struct Boom: Error {}
        let frames = FakeFrameSource()
        frames.state.withLock { $0.startError = Boom() }
        let observed = OSAllocatedUnfairLock<AsyncStream<PoseSourceEvent>?>(initialState: nil)
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })
        { stream in
            observed.withLock { $0 = stream }
        }

        await #expect(throws: Boom.self) {
            _ = try await source.start(PoseSourceConfiguration())
        }

        let stream = observed.withLock { $0 }
        if let stream {
            let events = await drain(stream)
            #expect(events == [.status(.starting), .status(.failed(.configurationFailed(String(describing: Boom()))))])
        } else {
            Issue.record("The stream observer was not called")
        }
    }

    @Test func sourceRecoversAfterAFailedStart() async throws {
        let frames = FakeFrameSource()
        frames.state.withLock { $0.startError = CameraError.noDevice }
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })
        await #expect(throws: CameraError.noDevice) {
            _ = try await source.start(PoseSourceConfiguration())
        }

        frames.state.withLock { $0.startError = nil }
        let stream = try await source.start(PoseSourceConfiguration())
        frames.emitFrame(timestamp: 7)
        await source.stop()

        let events = await drain(stream)
        #expect(events == [.status(.starting), sample(7), .status(.stopped)])
    }

    @Test func concurrentStartsAndStopsLeaveNothingCapturing() async {
        let frames = FakeFrameSource()
        let source = LivePoseSource(frameSource: frames, estimator: FakePoseEstimator(), isPowerConstrained: { false })

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = try? await source.start(PoseSourceConfiguration()) }
                group.addTask { await source.stop() }
            }
        }
        await source.stop()

        #expect(frames.frameHandler == nil)
        #expect(frames.stopCount >= 1)
    }
}
