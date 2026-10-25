import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel switch preview")
struct AppModelSwitchPreviewTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id

    /// A calibrated model with Live on and the camera running.
    private func liveHarness() async -> Harness {
        let h = Harness.make()
        h.openTrace()
        await h.startLive()
        return h
    }

    private func feed(_ h: Harness, at time: TimeInterval, face: Bool = true) {
        h.model.handle(.sample(Fixtures.sample(at: time, face: face)))
    }

    // MARK: Wiring

    @Test func withoutAProfileNothingIsDecidedAndTheSectionAsksForCalibration() async {
        let h = Harness.make()
        defer { h.tearDown() }
        await h.startLive()

        feed(h, at: 1)

        #expect(h.model.calibrationProfile == nil)
        #expect(!h.model.isSwitchPreviewActive)
        #expect(h.model.previewDecision == nil)
        #expect(h.engine.recorders.isEmpty)
        #expect(SwitchPreviewPresentation.noProfile == "Run the gate test to calibrate.")
    }

    @Test func everyLiveSampleGoesThroughTheDeciderWithTheSimulatedContext() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        let recorder = h.engine.lastRecorder
        #expect(recorder?.profile == Fixtures.profile())
        #expect(recorder?.settings == .default)

        feed(h, at: 1)
        feed(h, at: 1.1, face: false)

        #expect(recorder?.samples.map(\.timestamp) == [1, 1.1])
        #expect(recorder?.samples.map { $0.pose != nil } == [true, false])
        #expect(
            recorder?.contexts
                == Array(repeating: SwitchContext(focusedDisplay: nil, isFocusLocked: false, targets: nil), count: 2))
        #expect(h.model.previewDecision == Fixtures.decision())
    }

    @Test func theDeciderIsMadeWhenLiveStartsNotBefore() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        #expect(h.engine.recorders.count == 1)

        await h.model.setLiveEnabled(true)
        #expect(h.engine.recorders.count == 2)
    }

    @Test func theCameraRunningForAGateTestDoesNotFeedThePreview() async {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openTrace()
        await h.model.startGateTest()
        h.reportRunning()
        #expect(h.model.gateRunState == .running)
        let recorder = h.engine.lastRecorder

        feed(h, at: 1)

        #expect(recorder?.samples.isEmpty == true)
        #expect(h.engine.recorders.count == 1)
    }

    @Test func theGateTestDoesNotFeedThePreviewEvenWhileLiveIsOn() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        let recorder = h.engine.lastRecorder
        h.model.gateConfiguration = GateTestConfiguration(rounds: 1, holdDuration: 3)

        await h.model.startGateTest()
        h.reportRunning()
        feed(h, at: 1)

        #expect(h.model.gateRunState == .running)
        #expect(recorder?.samples.isEmpty == true)
        #expect(h.engine.lastRecorder?.samples.isEmpty == true)
    }

    // MARK: Switching

    @Test func aSwitchMovesTheSimulatedFocusAndLogsItWithItsDwellLatency() async throws {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            switch sample.timestamp {
            case 1.0: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 1.2: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0.5))
            case 1.4: Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 2.15))
            default: Fixtures.decision()
            }
        }

        feed(h, at: 1.0)
        feed(h, at: 1.2)
        #expect(h.model.simulatedFocus == nil)
        #expect(h.model.switchLog.isEmpty)
        feed(h, at: 1.4)

        #expect(h.model.simulatedFocus == right)
        let entry = try #require(h.model.switchLog.first)
        #expect(h.model.switchLog.count == 1)
        #expect(entry.displayName == "Right")
        #expect(abs(entry.latency - 0.4) < 1e-9)
        #expect(entry.time == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(SwitchPreviewPresentation.logText(entry) == "Switch to Right after 0.40 s")

        // The next sample carries the new simulated focus.
        feed(h, at: 1.5)
        #expect(h.engine.lastRecorder?.contexts.last?.focusedDisplay == right)
    }

    @Test func theLatencyRestartsWhenTheDwellWasLostAndBegunAgain() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            switch sample.timestamp {
            case 1.0: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 1.1: Fixtures.decision(reason: .noFace)
            case 2.0: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 2.4: Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 3.15))
            default: Fixtures.decision()
            }
        }

        for time in [1.0, 1.1, 2.0, 2.4] { feed(h, at: time) }

        #expect(abs((h.model.switchLog.first?.latency ?? -1) - 0.4) < 1e-9)
    }

    @Test func aDwellBegunAgainOnTheSameDisplayAfterAGapStartsItsLatencyAgain() async {
        // CONTRACT 6.6 step 4(a2): a supporting sample after a gap longer than maxGap drops the old dwell and starts a
        // fresh one on the same display, so the phase goes dwelling(progress 0.5) -> dwelling(progress 0) with no
        // idle phase in between.
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            switch sample.timestamp {
            case 1.0: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 1.2: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0.5))
            case 2.0: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 2.2: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0.5))
            case 2.4: Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 3.15))
            default: Fixtures.decision()
            }
        }

        for time in [1.0, 1.2, 2.0, 2.2, 2.4] { feed(h, at: time) }

        #expect(abs((h.model.switchLog.first?.latency ?? -1) - 0.4) < 1e-9)
    }

    @Test func aDwellThatMovesToAnotherDisplayStartsItsLatencyAgain() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            switch sample.timestamp {
            case 1.0: Fixtures.decision(phase: .dwelling(display: Fixtures.left.id, progress: 0))
            case 1.3: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 1.7: Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 2.45))
            default: Fixtures.decision()
            }
        }

        for time in [1.0, 1.3, 1.7] { feed(h, at: time) }

        #expect(abs((h.model.switchLog.first?.latency ?? -1) - 0.4) < 1e-9)
    }

    @Test func aSwitchWithoutAnObservedDwellHasZeroLatency() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in
            Fixtures.decision(switchTo: Fixtures.left.id, phase: .coolingDown(until: 9))
        }

        feed(h, at: 5)

        #expect(h.model.switchLog.first?.latency == 0)
        #expect(h.model.simulatedFocus == left)
    }

    @Test func theLogKeepsTheNewestTenEntriesNewestFirst() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            let target = Int(sample.timestamp) % 2 == 0 ? Fixtures.left.id : Fixtures.right.id
            return Fixtures.decision(switchTo: target, phase: .coolingDown(until: sample.timestamp + 1))
        }

        for time in 1...12 { feed(h, at: Double(time)) }

        #expect(h.model.switchLog.count == AppModel.switchLogLimit)
        #expect(h.model.switchLog.count == 10)
        // Sample 12 is the newest: even seconds go to Left.
        #expect(h.model.switchLog.map(\.displayName).prefix(3) == ["Left", "Right", "Left"])
        let ids = h.model.switchLog.map(\.id)
        #expect(ids == ids.sorted(by: >))
        #expect(Set(ids).count == 10)
    }

    // MARK: Lock and resets

    @Test func theLockToggleReachesTheDeciderInTheContext() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, context in
            Fixtures.decision(
                phase: context.isFocusLocked ? .locked : .idle, reason: context.isFocusLocked ? .focusLocked : nil)
        }

        feed(h, at: 1)
        #expect(h.model.previewDecision?.phase == .idle)

        h.model.simulateFocusLock = true
        feed(h, at: 1.1)

        #expect(h.engine.lastRecorder?.contexts.map(\.isFocusLocked) == [false, true])
        #expect(h.model.previewDecision?.phase == .locked)
        #expect(SwitchPreviewPresentation.phaseText(.locked, name: { _ in "" }) == "Focus lock is on")
    }

    @Test func aLayoutChangeResetsTheDeciderAndTheSimulatedFocus() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9)) }
        feed(h, at: 1)
        #expect(h.model.simulatedFocus == right)
        let recorder = h.engine.lastRecorder
        #expect(recorder?.resetCount == 0)

        h.model.layoutDidChange(Fixtures.threeDisplays)

        #expect(recorder?.resetCount == 1)
        #expect(h.model.simulatedFocus == nil)
        #expect(h.model.previewDecision == nil)
        // The log is history: it stays.
        #expect(h.model.switchLog.count == 1)
    }

    @Test func aStreamRestartResetsThePreview() async {
        let h = Harness.make(autoRun: true)
        defer { h.tearDown() }
        h.openTrace()
        await h.model.setLiveEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9)) }
        feed(h, at: 1)
        #expect(h.model.simulatedFocus == right)
        let recordersBefore = h.engine.recorders.count

        await h.model.selectCamera("cam-external")
        _ = await waitUntil { h.model.status.isRunning }

        #expect(h.model.simulatedFocus == nil)
        #expect(h.engine.recorders.count == recordersBefore + 1)
    }

    @Test func anInterruptionResetsTheDecider() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9)) }
        feed(h, at: 1)
        let recorder = h.engine.lastRecorder

        h.model.handle(.status(.interrupted("Camera disconnected")))

        #expect(recorder?.resetCount == 1)
        #expect(h.model.simulatedFocus == nil)
        #expect(h.model.previewDecision == nil)
    }

    @Test func turningLiveOffResetsAndStopsDeciding() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9)) }
        feed(h, at: 1)
        let recorder = h.engine.lastRecorder

        await h.model.setLiveEnabled(false)
        feed(h, at: 2)

        #expect((recorder?.resetCount ?? 0) >= 1)
        #expect(h.model.simulatedFocus == nil)
        #expect(recorder?.samples.count == 1)
    }

    // MARK: Safety

    @Test func thePreviewNeverTouchesRealFocus() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9)) }

        for time in 1...5 { feed(h, at: Double(time)) }

        #expect(h.model.switchLog.count == 5)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.focus.lastUsedWindowsCalls == 0)
        #expect(h.focus.focusedDisplayCalls == 0)
        #expect(h.focus.requestTrustCalls == 0)
        #expect(h.focus.isTrustedCalls == 0)
    }

    @Test func unknownDisplaysAreNamedPlainly() async {
        let h = await liveHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(switchTo: "unplugged", phase: .coolingDown(until: 9)) }

        feed(h, at: 1)

        #expect(h.model.switchLog.first?.displayName == "Unknown display")
        #expect(h.model.simulatedFocus == "unplugged")
    }
}
