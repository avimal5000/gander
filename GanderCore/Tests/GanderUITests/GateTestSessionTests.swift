import Foundation
import GanderModels
import Testing

@testable import GanderUI

@Suite("Gate test session")
struct GateTestSessionTests {
    private func makeSession(
        layout: DisplayLayout = Fixtures.twoDisplays,
        rounds: Int = 2,
        hold: TimeInterval = 3,
        clock: TestClock
    ) -> GateTestSession {
        GateTestSession(
            layout: layout,
            cameraName: "Test cam",
            configuration: GateTestConfiguration(rounds: rounds, holdDuration: hold),
            clock: clock.reading
        )
    }

    @Test func stepsAreRoundsTimesDisplaysInLayoutOrder() {
        let session = makeSession(layout: Fixtures.threeDisplays, rounds: 2, clock: TestClock())
        #expect(session.steps.count == 6)
        #expect(session.steps.map(\.round) == [1, 1, 1, 2, 2, 2])
        #expect(
            session.steps.map(\.display.id) == [Fixtures.left.id, Fixtures.right.id, Fixtures.far.id] + [
                Fixtures.left.id, Fixtures.right.id, Fixtures.far.id,
            ])
        #expect(session.steps.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(session.steps.map(\.displayNumber) == [1, 2, 3, 1, 2, 3])
    }

    @Test func layoutOrderIsLeftToRightEvenIfInputIsShuffled() {
        let shuffled = DisplayLayout(displays: [Fixtures.right, Fixtures.left])
        let session = makeSession(layout: shuffled, rounds: 1, clock: TestClock())
        #expect(session.steps.map(\.display.id) == [Fixtures.left.id, Fixtures.right.id])
    }

    @Test func startBeginsSettlingOnTheFirstStep() {
        let clock = TestClock()
        var session = makeSession(clock: clock)
        #expect(session.phase == .pending)
        #expect(session.currentStep == nil)
        session.start()
        #expect(session.phase == .settling)
        #expect(session.currentStep?.display.id == Fixtures.left.id)
        #expect(session.progress?.phase == .settle)
    }

    @Test func settleLastsOneAndAHalfSecondsThenHoldLastsTheConfiguredTime() {
        let clock = TestClock()
        var session = makeSession(hold: 4, clock: clock)
        session.start()

        clock.set(1.49)
        session.advance()
        #expect(session.phase == .settling)

        clock.set(1.5)
        session.advance()
        #expect(session.phase == .holding)

        clock.set(5.49)
        session.advance()
        #expect(session.phase == .holding)
        #expect(session.currentStep?.number == 1)

        clock.set(5.5)
        session.advance()
        #expect(session.phase == .settling)
        #expect(session.currentStep?.number == 2)
        #expect(session.currentStep?.display.id == Fixtures.right.id)
    }

    @Test func onlyHoldSamplesAreRecordedAndTheyKeepTheirStepLabel() throws {
        let clock = TestClock()
        var session = makeSession(rounds: 1, hold: 3, clock: clock)
        session.start()

        // Settle: discarded.
        clock.set(0.5)
        session.ingest(Fixtures.sample(at: 0.5, yaw: 99))
        clock.set(1.4)
        session.ingest(Fixtures.sample(at: 1.4, yaw: 99))

        // Hold on the left display: recorded.
        clock.set(1.5)
        session.ingest(Fixtures.sample(at: 1.5, yaw: -20))
        clock.set(2.5)
        session.ingest(Fixtures.sample(at: 2.5, yaw: -21))

        // The hold deadline passes: the next sample belongs to the right display's settle phase and is dropped.
        clock.set(4.5)
        session.ingest(Fixtures.sample(at: 4.5, yaw: 99))
        // Settle of the right display (1.5 s) ends at 6.0; hold records.
        clock.set(6.0)
        session.ingest(Fixtures.sample(at: 6.0, yaw: 20))
        clock.set(9.0)
        session.ingest(Fixtures.sample(at: 9.0, yaw: 99))

        #expect(session.phase == .finished)
        let trace = try #require(session.makeTrace())
        #expect(trace.segments.count == 2)
        #expect(trace.segments[0].displayID == Fixtures.left.id)
        #expect(trace.segments[0].round == 1)
        #expect(trace.segments[0].samples.map { $0.pose?.yaw } == [-20, -21])
        #expect(trace.segments[1].displayID == Fixtures.right.id)
        #expect(trace.segments[1].samples.map { $0.pose?.yaw } == [20])
    }

    @Test func samplesWithoutAFaceAreRecordedDuringHold() throws {
        let clock = TestClock()
        var session = makeSession(rounds: 1, hold: 3, clock: clock)
        session.start()
        clock.set(1.5)
        session.ingest(Fixtures.sample(at: 1.5, face: false))
        clock.set(2.0)
        session.ingest(Fixtures.sample(at: 2.0, face: true))
        let progress = try #require(session.progress)
        #expect(progress.recordedSamples == 2)
        #expect(progress.recordedFaces == 1)
    }

    @Test func fullRunBuildsATraceWithOneSegmentPerStepInOrder() throws {
        let clock = TestClock()
        var session = makeSession(rounds: 2, hold: 3, clock: clock)
        session.start()
        var guardCounter = 0
        while session.isActive, guardCounter < 1000 {
            clock.advance(by: 0.25)
            session.ingest(Fixtures.sample(at: clock.now))
            guardCounter += 1
        }
        #expect(session.phase == .finished)
        let id = UUID()
        let created = Date(timeIntervalSince1970: 42)
        let trace = try #require(session.makeTrace(id: id, createdAt: created))
        #expect(trace.id == id)
        #expect(trace.createdAt == created)
        #expect(trace.cameraName == "Test cam")
        #expect(trace.layout == Fixtures.twoDisplays)
        #expect(trace.segments.map(\.round) == [1, 1, 2, 2])
        #expect(
            trace.segments.map(\.displayID) == [
                Fixtures.left.id, Fixtures.right.id, Fixtures.left.id, Fixtures.right.id,
            ])
        // 3 s of hold at 4 samples per second.
        #expect(trace.segments.allSatisfy { $0.samples.count == 12 })
        #expect(session.currentStep == nil)
    }

    @Test func cancelStopsRecordingAndProducesNoTrace() {
        let clock = TestClock()
        var session = makeSession(clock: clock)
        session.start()
        clock.set(2)
        session.ingest(Fixtures.sample(at: 2))
        session.cancel()
        #expect(session.phase == .cancelled)
        #expect(session.makeTrace() == nil)
        #expect(session.progress == nil)

        clock.set(3)
        session.ingest(Fixtures.sample(at: 3))
        session.advance()
        #expect(session.phase == .cancelled)
        #expect(session.makeTrace() == nil)
    }

    @Test func aFinishedSessionCannotBeCancelled() {
        let clock = TestClock()
        var session = makeSession(layout: Fixtures.oneDisplay, rounds: 1, hold: 3, clock: clock)
        session.start()
        clock.set(1.5)
        session.advance()
        clock.set(4.5)
        session.advance()
        #expect(session.phase == .finished)
        session.cancel()
        #expect(session.phase == .finished)
        #expect(session.makeTrace() != nil)
    }

    @Test func progressReportsElapsedTimeAndPosition() throws {
        let clock = TestClock()
        var session = makeSession(rounds: 2, hold: 4, clock: clock)
        session.start()
        clock.set(0.5)
        var progress = try #require(session.progress)
        #expect(progress.phase == .settle)
        #expect(progress.phaseElapsed == 0.5)
        #expect(progress.phaseDuration == 1.5)
        #expect(progress.remaining == 1.0)
        #expect(progress.stepNumber == 1)
        #expect(progress.stepCount == 4)
        #expect(progress.round == 1)
        #expect(progress.rounds == 2)
        #expect(progress.displayNumber == 1)
        #expect(progress.displayCount == 2)

        clock.set(3.5)
        session.advance()
        clock.set(5.5)
        progress = try #require(session.progress)
        #expect(progress.phase == .hold)
        #expect(progress.phaseDuration == 4)
        #expect(progress.fraction == 0.5)
    }

    @Test func aLayoutWithoutDisplaysFinishesImmediatelyWithNoSegments() throws {
        var session = makeSession(layout: .empty, clock: TestClock())
        session.start()
        #expect(session.phase == .finished)
        let trace = try #require(session.makeTrace())
        #expect(trace.segments.isEmpty)
    }

    @Test func configurationIsClampedToTheAllowedRanges() {
        #expect(GateTestConfiguration(rounds: 0, holdDuration: 1).rounds == 1)
        #expect(GateTestConfiguration(rounds: 9, holdDuration: 99).rounds == 3)
        #expect(GateTestConfiguration(rounds: 2, holdDuration: 1).holdDuration == 3)
        #expect(GateTestConfiguration(rounds: 2, holdDuration: 99).holdDuration == 10)
        #expect(GateTestConfiguration() == GateTestConfiguration(rounds: 2, holdDuration: 5))
    }

    @Test func estimatedDurationCountsSettleAndHoldForEveryStep() {
        let configuration = GateTestConfiguration(rounds: 2, holdDuration: 5)
        #expect(configuration.estimatedDuration(displayCount: 2) == 4 * 6.5)
    }
}
