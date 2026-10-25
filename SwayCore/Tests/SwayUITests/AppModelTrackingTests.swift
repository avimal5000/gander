import AppKit
import Foundation
import Observation
import SwayModels
import Testing
import os

@testable import SwayUI

@MainActor
@Suite("AppModel tracking loop")
struct AppModelTrackingTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id
    private let far = Fixtures.far.id

    /// A calibrated model with Tracking on, the camera running, and the first focused-display poll done.
    private func trackingHarness(
        layout: DisplayLayout = Fixtures.twoDisplays, trusted: Bool = true, appActive: Bool = false
    ) async -> Harness {
        let h = Harness.make(layout: layout, trusted: trusted, calibrated: true, appActive: appActive)
        await h.startTracking()
        await h.settlePoll()
        return h
    }

    private func feed(_ h: Harness, at time: TimeInterval, face: Bool = true) {
        h.model.handle(.sample(Fixtures.sample(at: time, face: face)))
    }

    /// A decider that dwells on `target` from `dwellFrom` and fires at `fireAt`, then keeps asking to switch. Like the
    /// real one it goes idle while locked, unless `ignoresLock` makes it misbehave on purpose.
    private func scriptLook(
        _ h: Harness, at target: DisplayID, dwellFrom: Double = 1.0, fireAt: Double = 1.4, ignoresLock: Bool = false
    ) {
        h.engine.script.set { sample, context in
            if context.isFocusLocked, !ignoresLock { return Fixtures.decision(phase: .locked, reason: .focusLocked) }
            let look = Fixtures.classification(best: target)
            if sample.timestamp >= fireAt {
                return Fixtures.decision(
                    switchTo: target, phase: .coolingDown(until: sample.timestamp + 0.75), classification: look)
            }
            if sample.timestamp >= dwellFrom {
                let progress = (sample.timestamp - dwellFrom) / (fireAt - dwellFrom)
                return Fixtures.decision(phase: .dwelling(display: target, progress: progress), classification: look)
            }
            return Fixtures.decision(classification: look)
        }
    }

    private func focusedRight(app: String = "Safari", ms: Int = 120) -> FocusResult {
        .focused(
            Fixtures.window(7, app: app, title: "Secret page", on: Fixtures.right), method: .accessibilityRaise,
            milliseconds: ms)
    }

    // MARK: Switching

    @Test func aHeldLookFiresExactlyOneFocusRequestForTheRightDisplay() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)

        for time in [1.0, 1.2, 1.4, 1.5, 1.6] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.focus.focusCalls == [right])
        #expect(h.focus.focusLayouts == [Fixtures.twoDisplays])
        #expect(h.model.trackingFocus == right)
        #expect(h.model.loop.polled == right)
        #expect(!h.model.isSwitching)
        #expect(h.model.switchLog.count == 1)
    }

    @Test func theLogNamesTheAppAndTheDisplayAndHowLongTheLookWasHeldNeverTheTitle() async throws {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight(app: "Safari", ms: 120))
        scriptLook(h, at: right)

        for time in [1.0, 1.2, 1.4] { feed(h, at: time) }
        await h.settleSwitch()

        let entry = try #require(h.model.switchLog.first)
        #expect(entry.text == "Focused Safari on Right in 120 ms, held 0.40 s")
        #expect(!entry.text.contains("Secret"))
        #expect(entry.time == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func theNextSampleCarriesTheNewFocusAndTheTargets() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)
        for time in [1.0, 1.2, 1.4] { feed(h, at: time) }
        await h.settleSwitch()

        feed(h, at: 1.5)

        let context = h.engine.lastRecorder?.contexts.last
        #expect(context == SwitchContext(focusedDisplay: right, isFocusLocked: false, targets: nil))
    }

    @Test func noOtherRequestStartsWhileOneIsInFlightAndTheDeciderIsToldItIsLocked() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        for time in [1.0, 1.2, 1.4] { feed(h, at: time) }
        _ = await waitUntil { h.focus.isHoldingFocus }

        #expect(h.model.isSwitching)
        #expect(h.model.trackingHold == .switching)
        #expect(h.model.trackingFocus == right, "The request in flight")
        feed(h, at: 1.5)
        feed(h, at: 1.6)

        #expect(h.engine.lastRecorder?.contexts.suffix(2).map(\.isFocusLocked) == [true, true])
        #expect(h.focus.focusCalls == [right])
        h.focus.release()
        await h.settleSwitch()
        #expect(!h.model.isSwitching)
        #expect(h.model.trackingHold == nil)
    }

    @Test func aMisbehavingDeciderStillCannotStartASecondRequest() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right, ignoresLock: true)
        for time in [1.4, 1.5, 1.6] { feed(h, at: time) }
        _ = await waitUntil { h.focus.isHoldingFocus }

        #expect(h.focus.focusCalls == [right])
        h.focus.release()
        await h.settleSwitch()
    }

    // MARK: Holds

    @Test func noRequestWhileFocusLockIsOn() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.model.setFocusLock(true)
        scriptLook(h, at: right, ignoresLock: true)

        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.model.trackingHold == .focusLock)
        #expect(h.engine.lastRecorder?.contexts.allSatisfy(\.isFocusLocked) == true)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.model.switchLog.isEmpty)
    }

    @Test func noRequestWhileSwayIsTheActiveApp() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.appState.isActive = true
        h.notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        scriptLook(h, at: right, ignoresLock: true)

        #expect(h.model.isAppActive)
        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.model.trackingHold == .swayInFront)
        #expect(h.engine.lastRecorder?.contexts.allSatisfy(\.isFocusLocked) == true)
        #expect(h.focus.focusCalls.isEmpty)

        h.appState.isActive = false
        h.notifications.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!h.model.isAppActive)
        feed(h, at: 2.0)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "Resumes once another app is in front")
    }

    @Test func closingSwaysLastWindowReleasesTheHold() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.appState.isActive = true
        h.notifications.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        #expect(h.model.trackingHold == .swayInFront)

        // Still the active app, but its last window closed: nothing of Sway's is in front.
        h.appState.isActive = false
        h.notifications.post(name: NSWindow.didResignKeyNotification, object: nil)
        #expect(h.model.trackingHold == nil)
        scriptLook(h, at: right)
        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right])
    }

    @Test func swayBeingActiveAtLaunchHoldsFromTheStart() async {
        let h = await trackingHarness(appActive: true)
        defer { h.tearDown() }
        #expect(h.model.isAppActive)
        #expect(h.model.trackingHold == .swayInFront)
    }

    @Test func noRequestWhileAFocusTestRequestOrCountdownRuns() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        scriptLook(h, at: right, ignoresLock: true)

        h.model.focusActivity = .focusing(display: left)
        feed(h, at: 1.4)
        #expect(h.model.trackingHold == .focusTest)

        h.model.focusActivity = .countingDown(display: left, deadline: 99)
        feed(h, at: 1.5)
        #expect(h.model.trackingHold == .focusTest)

        #expect(h.engine.lastRecorder?.contexts.allSatisfy(\.isFocusLocked) == true)
        #expect(h.focus.focusCalls.isEmpty)

        h.model.focusActivity = .idle
        feed(h, at: 1.6)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right])
    }

    @Test func noRequestWithoutAccessibilityAndTheStatusSaysSo() async {
        let h = await trackingHarness(trusted: false)
        defer { h.tearDown() }
        scriptLook(h, at: right)

        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(!h.model.isAccessibilityTrusted)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(!h.model.isSwitching)
        #expect(h.model.trackingStatus == .needsAccessibility)
        #expect(h.model.menuBanner == .needsAccessibility)

        // Granting access shows up on the next tick, and the next hold goes through.
        h.focus.setTrusted(true)
        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.model.isAccessibilityTrusted)
        #expect(h.model.trackingStatus == .tracking)
        feed(h, at: 2.0)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right])
    }

    @Test func theHoldReasonsHavePriority() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        #expect(h.model.trackingHold == nil)

        h.model.isSwitching = true
        #expect(h.model.trackingHold == .switching)
        h.model.focusActivity = .focusing(display: left)
        #expect(h.model.trackingHold == .focusTest)
        h.model.isAppActive = true
        #expect(h.model.trackingHold == .swayInFront)
        h.model.focusLocked = true
        #expect(h.model.trackingHold == .focusLock)
    }

    // MARK: Results

    @Test func aDisplayWithNoWindowIsTreatedAsFocusedSoItIsNotRetried() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.noWindow(right))
        scriptLook(h, at: right)

        for time in [1.4, 1.5] { feed(h, at: time) }
        await h.settleSwitch()
        feed(h, at: 2.5)

        #expect(h.model.switchLog.first?.text == "No window on Right")
        #expect(h.model.trackingFocus == right)
        #expect(h.engine.lastRecorder?.contexts.last?.focusedDisplay == right)
        #expect(h.model.loop.polled == nil, "The real focus is still what the poll said")
    }

    @Test func theOverrideEndsWhenThePollSeesFocusSomewhereElse() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.noWindow(right))
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        await h.settleSwitch()
        #expect(h.model.trackingFocus == right)

        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.model.trackingFocus == right, "The poll still says what focus was before the attempt")

        h.focus.setFocusedDisplay(left)
        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.model.trackingFocus == left)
    }

    @Test func theOverrideEndsWhenTheLookMovesOnToAnotherDisplay() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.noWindow(right))
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        await h.settleSwitch()
        #expect(h.model.trackingFocus == right)

        h.engine.script.set { _, _ in
            Fixtures.decision(classification: Fixtures.classification(best: Fixtures.left.id, margin: 0.8))
        }
        feed(h, at: 2.0)

        #expect(h.model.trackingFocus == nil)
        #expect(h.model.loop.override == nil)
    }

    @Test func aFailureIsLoggedWithItsReason() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.failed(Fixtures.window(on: Fixtures.right), reason: "Focus did not move to Safari"))
        scriptLook(h, at: right)

        feed(h, at: 1.4)
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text == "Failed: Focus did not move to Safari")
        #expect(h.model.trackingFocus == right)
    }

    @Test func aNotTrustedResultTurnsTheAccessibilityFlagOff() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.notTrusted)
        scriptLook(h, at: right)

        feed(h, at: 1.4)
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text == "Accessibility permission needed")
        #expect(!h.model.isAccessibilityTrusted)
        #expect(h.model.trackingStatus == .needsAccessibility)
        #expect(h.model.trackingFocus == nil)
    }

    @Test func theSwitchLogKeepsTheNewestTenNewestFirst() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(.noWindow(right))
        h.engine.script.set { sample, _ in
            Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: sample.timestamp + 1))
        }

        for index in 1...12 {
            feed(h, at: Double(index))
            await h.settleSwitch()
            h.model.loop.reset()  // Starts the next request clean.
        }

        #expect(h.model.switchLog.count == AppModel.switchLogLimit)
        let ids = h.model.switchLog.map(\.id)
        #expect(ids == ids.sorted(by: >))
        #expect(Set(ids).count == 10)
    }

    // MARK: Hold time

    @Test func theHoldTimeCountsFromTheStartOfTheDwell() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
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
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text.hasSuffix("held 0.40 s") == true)
    }

    @Test func aDwellBegunAgainOnTheSameDisplayAfterAGapStartsItsHoldTimeAgain() async {
        // CONTRACT 6.6 step 4(a2): a supporting sample after a gap longer than maxGap drops the old dwell and starts a
        // fresh one on the same display, so the phase goes dwelling(progress 0.5) -> dwelling(progress 0).
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
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
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text.hasSuffix("held 0.40 s") == true)
    }

    @Test func aDwellThatMovesToAnotherDisplayStartsItsHoldTimeAgain() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        h.engine.script.set { sample, _ in
            switch sample.timestamp {
            case 1.0: Fixtures.decision(phase: .dwelling(display: Fixtures.left.id, progress: 0))
            case 1.3: Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0))
            case 1.7: Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 2.45))
            default: Fixtures.decision()
            }
        }

        for time in [1.0, 1.3, 1.7] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text.hasSuffix("held 0.40 s") == true)
    }

    @Test func aSwitchWithoutAnObservedDwellHasZeroHoldTime() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        h.engine.script.set { _, _ in
            Fixtures.decision(switchTo: Fixtures.right.id, phase: .coolingDown(until: 9))
        }

        feed(h, at: 5)
        await h.settleSwitch()

        #expect(h.model.switchLog.first?.text.hasSuffix("held 0.00 s") == true)
    }

    // MARK: Resets

    @Test func aLayoutChangeResetsTheLoopAndALateResultIsIgnored() async {
        let h = Harness.make(layout: Fixtures.threeDisplays, calibrated: true)
        defer { h.tearDown() }
        await h.startTracking()
        await h.settlePoll()
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        _ = await waitUntil { h.focus.isHoldingFocus }
        let request = h.model.focusSwitchTask
        #expect(h.model.isSwitching)

        h.model.layoutDidChange(Fixtures.twoDisplays)

        #expect(!h.model.isSwitching)
        #expect(h.model.trackingFocus == nil)
        h.focus.setResult(focusedRight())
        h.focus.release()
        await request?.value
        #expect(h.model.switchLog.isEmpty, "A result from before the reset says nothing about the new layout")
        #expect(h.model.trackingFocus == nil)
        #expect(h.model.loop.polled == nil)
    }

    @Test func aLayoutChangeThatKeepsTheCalibrationStillResetsTheDecider() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.engine.script.set { _, _ in Fixtures.decision(phase: .dwelling(display: Fixtures.right.id, progress: 0.5)) }
        feed(h, at: 1)
        let recorder = h.engine.lastRecorder
        let resets = recorder?.resetCount ?? 0
        #expect(h.model.previewDecision != nil)
        let moved = DisplayInfo(
            id: Fixtures.right.id, cgDisplayID: 12, name: "Right",
            frame: CGRect(x: 1920, y: 0, width: 1280, height: 720),
            isBuiltIn: false, isMain: false)

        h.model.layoutDidChange(DisplayLayout(displays: [Fixtures.left, moved]))

        #expect(recorder?.resetCount == resets + 1)
        #expect(h.model.previewDecision == nil)
        #expect(h.model.lookSummary == .off)
    }

    @Test func aStreamRestartAndAnInterruptionResetTheLoop() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        _ = await waitUntil { h.focus.isHoldingFocus }
        let request = h.model.focusSwitchTask
        let recorder = h.engine.lastRecorder

        h.model.handle(.status(.interrupted("Camera disconnected")))

        #expect(!h.model.isSwitching)
        #expect(recorder?.resetCount == 1)
        #expect(h.model.previewDecision == nil)
        h.focus.release()
        await request?.value
        #expect(h.model.switchLog.isEmpty)

        // Running again: a fresh poll, and a fresh decider after a restart.
        h.model.handle(.status(.running(Fixtures.builtInCamera)))
        let before = h.engine.recorders.count
        await h.model.enqueueCameraWork { await $0.restartPoseSource() }.value
        #expect(h.engine.recorders.count == before + 1)
    }

    @Test func turningTrackingOffResetsAndStopsDeciding() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        scriptLook(h, at: right)
        feed(h, at: 1.2)
        let recorder = h.engine.lastRecorder

        await h.model.setTrackingEnabled(false)
        feed(h, at: 1.4)

        #expect((recorder?.resetCount ?? 0) >= 1)
        #expect(recorder?.samples.count == 1)
        #expect(h.model.previewDecision == nil)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(h.model.lookSummary == .off)
    }

    // MARK: Gate test holds tracking

    @Test func theGateTestHoldsTrackingWhileItRuns() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let recorder = h.engine.lastRecorder
        scriptLook(h, at: right)
        h.model.gateConfiguration = GateTestConfiguration(rounds: 1, holdDuration: 3)

        await h.model.startGateTest()
        h.reportRunning()
        feed(h, at: 1.4)
        await h.settleSwitch()

        #expect(h.model.gateRunState == .running)
        #expect(recorder?.samples.isEmpty == true)
        #expect(h.engine.lastRecorder?.samples.isEmpty == true)
        #expect(h.focus.focusCalls.isEmpty)
        #expect(!h.model.isTrackingActive)
        #expect(h.model.trackingStatus == .calibrating)
    }

    // MARK: Targets (SPEC D22)

    @Test func twoAndThreeDisplaysAreAllTargetsAndAFourthIsLeftOut() async {
        for (layout, expected) in [
            (Fixtures.twoDisplays, nil),
            (Fixtures.threeDisplays, nil),
            (Fixtures.fourDisplays, Set([Fixtures.left.id, Fixtures.right.id, Fixtures.far.id])),
        ] as [(DisplayLayout, Set<DisplayID>?)] {
            let h = await trackingHarness(layout: layout)
            defer { h.tearDown() }

            feed(h, at: 1)

            #expect(h.engine.lastRecorder?.contexts.last?.targets == expected, "\(layout.displays.count) displays")
        }
    }

    @Test func unplugPartOfACalibrationAndTheRemainingDisplaysAreTheTargets() async {
        let h = await trackingHarness(layout: Fixtures.fourDisplays)
        defer { h.tearDown() }

        h.model.layoutDidChange(Fixtures.threeDisplays)
        feed(h, at: 1)

        #expect(h.engine.lastRecorder?.contexts.last?.targets == nil)
        #expect(h.engine.lastRecorder?.profile.displayIDs == [left, right, far])
    }

    // MARK: Focused-display poll

    @Test func thePollRunsOnlyWhileTrackingRuns() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.trackingTick()
        #expect(h.focus.isTrustedCalls == 0, "Tracking is off")
        #expect(h.focus.focusedDisplayCalls == 0)

        await h.model.setTrackingEnabled(true)
        h.model.trackingTick()
        #expect(h.focus.focusedDisplayCalls == 0, "The camera is not running yet")

        h.reportRunning()
        await h.settlePoll()
        #expect(h.focus.focusedDisplayCalls == 1, "One poll at once when tracking starts")
        #expect(h.focus.isTrustedCalls == 1)

        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.focus.focusedDisplayCalls == 2)
        #expect(h.focus.isTrustedCalls == 2)

        await h.model.setTrackingEnabled(false)
        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.focus.focusedDisplayCalls == 2)
        #expect(h.focus.isTrustedCalls == 2)
    }

    @Test func theCameraLeavingTheRunningStateStopsThePoll() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let calls = h.focus.focusedDisplayCalls

        h.model.handle(.status(.suspended(.systemSleep)))
        h.model.trackingTick()
        await h.settlePoll()
        #expect(h.focus.focusedDisplayCalls == calls)

        h.model.handle(.status(.running(Fixtures.builtInCamera)))
        await h.settlePoll()
        #expect(h.focus.focusedDisplayCalls == calls + 1, "Polls again at once when tracking resumes")
    }

    @Test func aTickWhileAPollIsStillRunningDoesNotStartAnother() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let calls = h.focus.focusedDisplayCalls

        h.model.trackingTick()
        h.model.trackingTick()
        h.model.trackingTick()
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == calls + 1)
        #expect(h.focus.isTrustedCalls >= 4, "Trust is refreshed on every tick")
    }

    @Test func anAppActivationTriggersOnePoll() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let calls = h.focus.focusedDisplayCalls
        h.focus.setFocusedDisplay(right)

        h.workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == calls + 1)
        #expect(h.model.trackingFocus == right)
    }

    @Test func anAppActivationWhileNotTrackingPollsNothing() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == 0)
    }

    @Test func thePolledDisplayIsTheFocusTheDeciderSees() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(left)
        await h.startTracking()
        await h.settlePoll()

        feed(h, at: 1)

        #expect(h.model.trackingFocus == left)
        #expect(h.engine.lastRecorder?.contexts.last?.focusedDisplay == left)
    }

    @Test func aPollThatStartedBeforeASwitchCannotUndoIt() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)
        h.focus.setFocusedDisplay(left)

        h.model.trackingTick()  // Starts a poll that will answer "left".
        feed(h, at: 1.4)  // Starts and finishes a switch to right before that poll is applied.
        await h.settleSwitch()
        await h.settlePoll()

        #expect(h.model.trackingFocus == right)
    }

    // MARK: Safety

    @Test func trackingNeverAsksForAccessibilityOrReadsTheWindowList() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)

        for time in [1.0, 1.4, 2.5, 3.5] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.focus.requestTrustCalls == 0)
        #expect(h.focus.lastUsedWindowsCalls == 0)
    }

    // MARK: What the always-alive views read

    private func changes<T: Sendable>(
        _ read: @escaping @MainActor () -> T, during work: @MainActor () -> Void
    ) -> Int {
        let count = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = read()
        } onChange: {
            count.withLock { $0 += 1 }
        }
        work()
        return count.withLock { $0 }
    }

    @Test func theLookLineChangesOnlyWhenTheSummaryChanges() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.engine.script.set { sample, _ in
            let best = sample.timestamp < 100 ? Fixtures.left.id : Fixtures.right.id
            return Fixtures.decision(classification: Fixtures.classification(best: best))
        }
        feed(h, at: 1)
        #expect(h.model.lookSummary == .display("Left"))

        let sameLook = changes({ h.model.lookSummary }) {
            for time in 2...30 { feed(h, at: Double(time)) }
        }
        #expect(sameLook == 0, "The same summary on every frame is not a change")

        let newLook = changes({ h.model.lookSummary }) { feed(h, at: 101) }
        #expect(newLook == 1)
        #expect(h.model.lookSummary == .display("Right"))

        h.engine.script.set { _, _ in Fixtures.decision(classification: Fixtures.classification(.elsewhere)) }
        feed(h, at: 102)
        #expect(h.model.lookSummary == .elsewhere)
        h.engine.script.set { _, _ in Fixtures.decision(classification: .noFace) }
        feed(h, at: 103, face: false)
        #expect(h.model.lookSummary == .noFace)
    }

    @Test func theMenuBarStatusDoesNotChangeAtTheFrameRate() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        scriptLook(h, at: right, dwellFrom: 1000, fireAt: 2000)
        feed(h, at: 0.1)
        #expect(h.model.trackingStatus == .tracking)

        let changed = changes({ h.model.trackingStatus.symbol + h.model.statusLine + String(h.model.hasFace) }) {
            for index in 1...60 {
                h.model.handle(
                    .sample(
                        Fixtures.sample(at: 0.1 + Double(index) / 15, yaw: Double(index % 7), pitch: Double(index % 5)))
                )
            }
        }

        #expect(changed == 0, "The menu bar label must not redraw for every frame")
    }

    @Test func thePopoverBannerAndLookInputsDoNotChangeAtTheFrameRate() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        scriptLook(h, at: right, dwellFrom: 1000, fireAt: 2000)
        feed(h, at: 0.1)

        let changed = changes({
            (h.model.menuBanner, h.model.lookSummary, h.model.focusLocked) as (MenuBanner?, LookSummary, Bool)
        }) {
            for index in 1...60 { feed(h, at: 0.1 + Double(index) / 15) }
        }

        #expect(changed == 0)
    }

    @Test func aFaceComingAndGoingDoesChangeTheStatus() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        feed(h, at: 1)
        #expect(h.model.trackingStatus == .tracking)

        feed(h, at: 2, face: false)
        #expect(h.model.trackingStatus == .noFace)
        #expect(h.model.menuBarSymbol == "eye.trianglebadge.exclamationmark")
    }
}
