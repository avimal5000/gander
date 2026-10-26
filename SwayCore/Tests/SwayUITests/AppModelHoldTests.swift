import AppKit
import Foundation
import SwayModels
import Testing

@testable import SwayUI

/// CONTRACT 6.5.5 item 1: switching waits while the displays or the Spaces change (SPEC D44).
@MainActor
@Suite("AppModel display and Space holds")
struct AppModelHoldTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id
    private let screenParameters = NSApplication.didChangeScreenParametersNotification
    private let spaceChange = NSWorkspace.activeSpaceDidChangeNotification

    /// A calibrated model with Tracking on, the camera running, and the first focused-display poll done.
    private func trackingHarness() async -> Harness {
        let h = Harness.make(calibrated: true)
        await h.startTracking()
        await h.settlePoll()
        return h
    }

    private func feed(_ h: Harness, at time: TimeInterval) {
        h.model.handle(.sample(Fixtures.sample(at: time)))
    }

    /// A decider that dwells on `target` from 1.0 s and fires at 1.4 s, and keeps asking to switch. It ignores the lock
    /// on purpose, so a test sees that the model, not the decider, refuses the request.
    private func scriptLook(_ h: Harness, at target: DisplayID) {
        h.engine.script.set { sample, _ in
            let look = Fixtures.classification(best: target)
            if sample.timestamp >= 1.4 {
                return Fixtures.decision(
                    switchTo: target, phase: .coolingDown(until: sample.timestamp + 0.75), classification: look)
            }
            return Fixtures.decision(classification: look)
        }
    }

    private func focusedRight() -> FocusResult {
        .focused(Fixtures.window(7, app: "Safari", on: Fixtures.right), method: .appActivation, milliseconds: 120)
    }

    /// The same two displays, the right one smaller: a new layout the calibration still fits.
    private var rearranged: DisplayLayout {
        let smaller = DisplayInfo(
            id: Fixtures.right.id, cgDisplayID: 12, name: "Right",
            frame: CGRect(x: 1920, y: 0, width: 1280, height: 720), isBuiltIn: false, isMain: false)
        return DisplayLayout(displays: [Fixtures.left, smaller])
    }

    // MARK: Displays changing

    @Test func aScreenParameterChangeHoldsSwitchingAndLocksTheDecider() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)

        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.model.trackingHold == .displaysChanging)
        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()

        #expect(h.engine.lastRecorder?.contexts.allSatisfy(\.isFocusLocked) == true)
        #expect(h.focus.focusCalls.isEmpty, "No switch while the displays change")
        #expect(h.model.switchLog.isEmpty)
    }

    @Test func theHoldEndsWhenTheNewLayoutIsApplied() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)
        h.notifications.post(name: screenParameters, object: nil)

        h.model.layoutDidChange(rearranged)

        #expect(h.model.trackingHold == nil)
        #expect(!h.scheduler.hasPending, "The wait is cancelled with the hold")
        feed(h, at: 1.4)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "Switching is back")
    }

    @Test func theHoldEndsAfterThreeQuartersOfASecondWhenNoLayoutArrives() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.scheduler.pendingDelays == [AppModel.displaysChangingTimeout])
        #expect(AppModel.displaysChangingTimeout == 0.75)

        h.scheduler.advance(by: 0.74)
        #expect(h.model.trackingHold == .displaysChanging)
        h.scheduler.advance(by: 0.01)
        #expect(h.model.trackingHold == nil)
    }

    @Test func aLayoutThatDidNotChangeDoesNotEndTheHold() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.notifications.post(name: screenParameters, object: nil)

        h.model.layoutDidChange(Fixtures.twoDisplays)

        #expect(h.model.trackingHold == .displaysChanging, "Nothing new is known yet")
        h.scheduler.advance(by: 0.75)
        #expect(h.model.trackingHold == nil)
    }

    @Test func anotherNotificationRestartsTheWait() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.notifications.post(name: screenParameters, object: nil)
        h.scheduler.advance(by: 0.5)

        h.notifications.post(name: screenParameters, object: nil)
        h.scheduler.advance(by: 0.5)
        #expect(h.model.trackingHold == .displaysChanging, "0.5 s into the second wait")

        h.scheduler.advance(by: 0.25)
        #expect(h.model.trackingHold == nil)
    }

    @Test func startingTheHoldResetsTheLoopAndDropsASwitchInFlight() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        _ = await waitUntil { h.focus.isHoldingFocus }
        let request = h.model.focusSwitchTask
        let recorder = h.engine.lastRecorder
        let resets = recorder?.resetCount ?? 0
        #expect(h.model.isSwitching)

        h.notifications.post(name: screenParameters, object: nil)

        #expect(!h.model.isSwitching)
        #expect(h.model.trackingFocus == nil)
        #expect(h.model.previewDecision == nil)
        #expect(recorder?.resetCount == resets + 1, "The dwell and cooldown are gone, as after a layout change")
        h.focus.setResult(focusedRight())
        h.focus.release()
        await request?.value
        #expect(h.focus.focusCancelled == [true], "The switch was told to stop")
        #expect(h.model.switchLog.isEmpty, "A result from before the change says nothing about the new layout")
        #expect(h.model.loop.polled == nil)
    }

    @Test func focusIsPolledOnceTheHoldEnds() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(right)
        h.notifications.post(name: screenParameters, object: nil)
        let calls = h.focus.focusedDisplayCalls
        #expect(h.model.trackingFocus == nil, "Unknown while the layout settles")

        h.scheduler.advance(by: 0.75)
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == calls + 1)
        #expect(h.model.trackingFocus == right)
    }

    @Test func focusIsPolledWhenTheLayoutEndsTheHoldToo() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(left)
        h.notifications.post(name: screenParameters, object: nil)
        let calls = h.focus.focusedDisplayCalls

        h.model.layoutDidChange(rearranged)
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == calls + 1, "One poll, not one for the layout and one for the hold")
        #expect(h.model.trackingFocus == left)
    }

    @Test func aLayoutChangeWithoutANotificationLeavesNoHold() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.model.layoutDidChange(rearranged)

        #expect(h.model.trackingHold == nil)
        #expect(!h.scheduler.hasPending)
    }

    // MARK: The cap (CONTRACT 6.5.5 item 1, cap and log)

    /// Moves both the clock (which the cap reads) and the scheduler (which runs the timers) forward.
    private func advance(_ h: Harness, by seconds: TimeInterval) {
        h.clock.advance(by: seconds)
        h.scheduler.advance(by: seconds)
    }

    @Test func repeatedNotificationsEveryHalfSecondEndTheHoldThreeSecondsAfterTheFirst() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        let recorder = h.engine.lastRecorder
        let resets = recorder?.resetCount ?? 0
        #expect(AppModel.displaysChangingCap == 3)

        for index in 0..<6 {
            h.notifications.post(name: screenParameters, object: nil)  // At 0, 0.5, ... 2.5 s.
            #expect(h.model.trackingHold == .displaysChanging, "Notification \(index)")
            if index < 5 { advance(h, by: 0.5) }
        }
        #expect(recorder?.resetCount == resets + 6, "Every notification inside the cap still resets the loop")
        #expect(h.scheduler.pendingDelays == [0.5], "The last wait is cut to what is left of the 3 s")

        advance(h, by: 0.49)
        #expect(h.model.trackingHold == .displaysChanging)
        advance(h, by: 0.01)
        #expect(h.model.trackingHold == nil, "Three seconds after the first notification")
    }

    @Test func afterTheCapTheSameChatterNeitherHoldsNorResetsAndSwitchingWorks() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)
        for _ in 0..<6 {
            h.notifications.post(name: screenParameters, object: nil)
            advance(h, by: 0.5)
        }
        #expect(h.model.trackingHold == nil, "Capped at 3 s")
        let recorder = h.engine.lastRecorder
        let resets = recorder?.resetCount ?? 0

        for _ in 0..<6 {  // The display keeps posting every 0.5 s with the same layout.
            h.notifications.post(name: screenParameters, object: nil)
            #expect(h.model.trackingHold == nil)
            advance(h, by: 0.5)
        }
        #expect(recorder?.resetCount == resets, "Ignored, not reset")
        #expect(!h.scheduler.hasPending)

        feed(h, at: 1.4)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "Switching works while the display chatters")
    }

    @Test func aPauseInTheChatterLetsTheNextNotificationHoldAgain() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        for _ in 0..<6 {
            h.notifications.post(name: screenParameters, object: nil)
            advance(h, by: 0.5)
        }
        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.model.trackingHold == nil, "Still the same chatter")

        advance(h, by: AppModel.displaysChangingTimeout)
        h.notifications.post(name: screenParameters, object: nil)

        #expect(h.model.trackingHold == .displaysChanging, "A real change after a quiet moment")
    }

    @Test func aHoldThatEndedByItsLayoutOrItsTimeoutDoesNotIgnoreTheNextNotification() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.notifications.post(name: screenParameters, object: nil)
        h.model.layoutDidChange(rearranged)
        #expect(h.model.trackingHold == nil)

        advance(h, by: 0.1)
        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.model.trackingHold == .displaysChanging)

        advance(h, by: AppModel.displaysChangingTimeout)
        #expect(h.model.trackingHold == nil)
        advance(h, by: 0.1)
        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.model.trackingHold == .displaysChanging)
    }

    @Test func theHoldIsPolledAtItsCapToo() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(right)
        for _ in 0..<6 {
            h.notifications.post(name: screenParameters, object: nil)
            advance(h, by: 0.5)
        }
        await h.settlePoll()

        #expect(h.model.trackingFocus == right, "Focus is read again when the cap ends the hold")
    }

    // MARK: Spaces changing

    @Test func aSpaceChangeHoldsForSixTenthsOfASecond() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setResult(focusedRight())
        scriptLook(h, at: right)

        h.workspace.post(name: spaceChange, object: nil)
        #expect(h.model.trackingHold == .spaceChanging)
        #expect(h.scheduler.pendingDelays == [AppModel.spaceChangingDuration])
        #expect(AppModel.spaceChangingDuration == 0.6)
        for time in [1.0, 1.4, 1.6] { feed(h, at: time) }
        await h.settleSwitch()
        #expect(h.focus.focusCalls.isEmpty, "No switch while the Space settles")
        #expect(h.engine.lastRecorder?.contexts.allSatisfy(\.isFocusLocked) == true)

        h.scheduler.advance(by: 0.59)
        #expect(h.model.trackingHold == .spaceChanging)
        h.scheduler.advance(by: 0.01)
        #expect(h.model.trackingHold == nil)

        feed(h, at: 2.0)
        await h.settleSwitch()
        #expect(h.focus.focusCalls == [right], "Switching is back")
    }

    @Test func theSpaceHoldEndsWithOnePollOfTheFocusedDisplay() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(right)
        h.workspace.post(name: spaceChange, object: nil)
        let calls = h.focus.focusedDisplayCalls

        h.scheduler.advance(by: 0.6)
        await h.settlePoll()

        #expect(h.focus.focusedDisplayCalls == calls + 1)
        #expect(h.model.trackingFocus == right)
    }

    @Test func aPollThatBeganBeforeTheSpaceChangeIsDropped() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.setFocusedDisplay(right)
        h.model.trackingTick()  // Starts a poll that will answer "right".
        let stale = h.model.trackingPollTask

        h.workspace.post(name: spaceChange, object: nil)
        await stale?.value

        #expect(h.model.loop.polled == nil, "It may have seen the old Space")
        #expect(h.model.trackingFocus == nil)
    }

    @Test func anotherSpaceChangeRestartsTheHold() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.workspace.post(name: spaceChange, object: nil)
        h.scheduler.advance(by: 0.4)

        h.workspace.post(name: spaceChange, object: nil)
        h.scheduler.advance(by: 0.4)
        #expect(h.model.trackingHold == .spaceChanging)

        h.scheduler.advance(by: 0.2)
        #expect(h.model.trackingHold == nil)
    }

    @Test func aSpaceChangeDoesNotResetTheLoopOrDropASwitchInFlight() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        _ = await waitUntil { h.focus.isHoldingFocus }
        let request = h.model.focusSwitchTask
        h.focus.setResult(focusedRight())

        h.workspace.post(name: spaceChange, object: nil)
        h.focus.release()
        await request?.value

        #expect(h.model.switchLog.count == 1)
        #expect(h.model.trackingFocus == right)
    }

    @Test func aSpaceChangeDuringAnInFlightSwitchLocksTheDeciderButLetsTheSwitchFinish() async {
        // Pins what happens today: the Space hold ranks above `.switching`, so the decider is told it is locked (and a
        // real decider resets on that), while the model leaves the loop and the request alone. A change here is deliberate.
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.focus.holdFocusRequests()
        scriptLook(h, at: right)
        feed(h, at: 1.4)
        _ = await waitUntil { h.focus.isHoldingFocus }
        let request = h.model.focusSwitchTask
        let recorder = h.engine.lastRecorder
        let resets = recorder?.resetCount ?? 0
        #expect(h.model.trackingHold == .switching)

        h.workspace.post(name: spaceChange, object: nil)
        feed(h, at: 1.5)

        #expect(h.model.trackingHold == .spaceChanging, "Ranks above Switching")
        #expect(
            recorder?.contexts.last == SwitchContext(focusedDisplay: right, isFocusLocked: true, targets: nil),
            "Locked, with the request in flight still believed focused")
        #expect(recorder?.resetCount == resets, "The model never resets the decider for a Space change")
        #expect(h.model.isSwitching, "The loop is untouched")
        #expect(h.focus.focusCalls == [right], "The decider's repeated request is refused")

        h.focus.setResult(focusedRight())
        h.focus.release()
        await request?.value
        #expect(h.focus.focusCancelled == [false], "The request was not cancelled")
        #expect(h.model.switchLog.count == 1, "Its result still counts")
        #expect(h.model.trackingFocus == right)
        #expect(h.model.loop.polled == right)
        #expect(h.model.trackingHold == .spaceChanging, "Still settling after the switch")

        h.scheduler.advance(by: 0.6)
        #expect(h.model.trackingHold == nil)
        feed(h, at: 1.6)
        #expect(recorder?.contexts.last == SwitchContext(focusedDisplay: right, isFocusLocked: false, targets: nil))
    }

    // MARK: Both

    @Test func bothHoldsAreInvisibleInTheMenu() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        feed(h, at: 1)
        let status = h.model.trackingStatus
        let line = h.model.statusLine
        let glyph = h.model.menuBarGlyph
        #expect(status == .tracking)

        h.notifications.post(name: screenParameters, object: nil)
        #expect(h.model.trackingStatus == status)
        #expect(h.model.statusLine == line)
        #expect(h.model.menuBarGlyph == glyph)
        #expect(h.model.menuBanner == nil)

        h.workspace.post(name: spaceChange, object: nil)
        #expect(h.model.trackingStatus == status)
        #expect(h.model.statusLine == line)
        #expect(h.model.menuBanner == nil)
    }

    @Test func theHoldsRankAfterFocusTestAndBeforeSwitching() async {
        let h = await trackingHarness()
        defer { h.tearDown() }

        h.model.isSwitching = true
        #expect(h.model.trackingHold == .switching)
        h.model.spaceChanging = true
        #expect(h.model.trackingHold == .spaceChanging)
        h.model.displaysChanging = true
        #expect(h.model.trackingHold == .displaysChanging)
        h.model.focusActivity = .focusing(display: left)
        #expect(h.model.trackingHold == .focusTest)
        h.model.isAppActive = true
        #expect(h.model.trackingHold == .swayInFront)
        h.model.focusLocked = true
        #expect(h.model.trackingHold == .focusLock)
    }

    @Test func quittingDropsTheHoldsAndTheirTimers() async {
        let h = await trackingHarness()
        defer { h.tearDown() }
        h.notifications.post(name: screenParameters, object: nil)
        h.workspace.post(name: spaceChange, object: nil)
        #expect(h.scheduler.hasPending)

        h.model.applicationWillTerminate()

        #expect(!h.scheduler.hasPending)
        #expect(h.model.trackingHold == nil)
    }
}

@Suite("Hold log")
struct HoldLogTests {
    @Test func aStartNamesTheHold() {
        #expect(HoldLog.started(.displays) == "Display hold started")
        #expect(HoldLog.started(.space) == "Space hold started")
    }

    @Test func anEndNamesTheHoldTheReasonAndTheDuration() {
        #expect(HoldLog.ended(.displays, by: .layout, after: 0.42) == "Display hold ended by layout after 0.42 s")
        #expect(HoldLog.ended(.displays, by: .timeout, after: 0.75) == "Display hold ended by timeout after 0.75 s")
        #expect(HoldLog.ended(.displays, by: .cap, after: 3) == "Display hold ended by cap after 3.00 s")
        #expect(HoldLog.ended(.space, by: .timeout, after: 0.6) == "Space hold ended by timeout after 0.60 s")
    }

    @Test func aClockThatWentBackwardsIsLoggedAsZero() {
        #expect(HoldLog.ended(.space, by: .timeout, after: -1) == "Space hold ended by timeout after 0.00 s")
    }
}
