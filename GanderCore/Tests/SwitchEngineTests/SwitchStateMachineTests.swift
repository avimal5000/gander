import Foundation
import GanderModels
import Testing

@testable import SwitchEngine

/// One test per rule of the switch state machine (CONTRACT section 6.6). The hand profile and the 0.125 s
/// timestamp grid keep every comparison exact. Settings are the defaults with `dwell` 0.5: `enterMargin` 0.30,
/// `stayMargin` 0.15, `maxGap` 0.25, `cooldown` 0.75. Streams are continuous (no skipped frames).
@Suite struct SwitchStateMachineTests {
    private let a = HandProfile.a
    private let b = HandProfile.b
    private let c = HandProfile.c

    // MARK: Dwell

    @Test func firesAtExactlyTheFirstSampleWhereTheDwellHasElapsed() {
        var harness = DeciderHarness()  // focus on B, looking at A
        let decisions = harness.run(from: 0, to: 0.5, HandProfile.yawA)
        #expect(decisions.count == 5)
        for (decision, progress) in zip(decisions.dropLast(), [0.0, 0.25, 0.5, 0.75]) {
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .dwelling(display: a, progress: progress))
            #expect(decision.reason == .dwelling)
        }
        let fired = decisions[4]  // t - start == dwell
        #expect(fired.switchTo == a)
        #expect(fired.phase == .coolingDown(until: 1.25))
        #expect(fired.reason == nil)
        #expect(fired.classification.best == a)
    }

    @Test func firesOnTheBoundaryFrameWhenTheDifferenceOfLargeTimestampsRoundsBelowTheDwell() {
        // Host-uptime timestamps near 3e5 s resolve about 6e-11 s, so two stamps exactly 0.4 s apart can differ by
        // 0.39999999996 in doubles. That frame must still complete the 0.4 s dwell, not fire one frame late.
        let start = 310_297.743
        let boundary = (start + 0.4).nextDown
        #expect(boundary - start < 0.4)
        #expect(0.4 - (boundary - start) < 1e-9)

        var harness = DeciderHarness(settings: .default)
        var stamps = (0..<6).map { start + Double($0) * 0.4 / 6 }  // 6 frames, 0.0667 s apart
        stamps.append(boundary)
        let decisions = stamps.map { harness.feed($0, HandProfile.yawA) }
        #expect(decisions[0].phase == .dwelling(display: a, progress: 0))
        #expect(decisions.dropLast().allSatisfy { $0.switchTo == nil })
        let fired = decisions[6]
        #expect(fired.switchTo == a)
        #expect(fired.phase == .coolingDown(until: boundary + SwitchSettings.default.cooldown))
    }

    @Test func theDwellClockStartsAtTheFirstQualifyingSampleNotAtZero() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 9.875, HandProfile.yawB)  // looking at the focused display
        let decisions = harness.run(from: 10, to: 10.5, HandProfile.yawA)
        #expect(decisions[0].phase == .dwelling(display: a, progress: 0))
        #expect(decisions.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(decisions[4].switchTo == a)
    }

    @Test func aGlanceShorterThanTheDwellNeverFires() {
        var harness = DeciderHarness()
        let glance = harness.run(from: 0, to: 0.375, HandProfile.yawA)  // one frame short of the dwell
        #expect(glance.allSatisfy { $0.switchTo == nil })
        let back = harness.feed(0.5, HandProfile.yawB)
        #expect(back.switchTo == nil)
        #expect(back.phase == .idle)
        #expect(back.reason == .alreadyFocused)

        // A second look starts from scratch rather than resuming the first.
        let again = harness.run(from: 0.625, to: 1.125, HandProfile.yawA)
        #expect(again[0].phase == .dwelling(display: a, progress: 0))
        #expect(again[3].phase == .dwelling(display: a, progress: 0.75))
        #expect(again.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(again[4].switchTo == a)
    }

    // MARK: Gaps

    @Test func aGapNoLongerThanMaxGapSurvivesAndTheSwitchWaitsForASupportingSample() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)  // last support at 0.125
        let first = harness.feed(0.25, nil)  // no face, gap 0.125
        #expect(first.switchTo == nil)
        #expect(first.phase == .dwelling(display: a, progress: 0.5))
        #expect(first.reason == .dwelling)
        let second = harness.feed(0.375, HandProfile.yawA)  // support again after exactly maxGap: not "greater than"
        #expect(second.switchTo == nil)
        #expect(second.phase == .dwelling(display: a, progress: 0.75))  // the original clock kept running
        #expect(harness.feed(0.5, HandProfile.yawA).switchTo == a)
    }

    @Test func aSupportingSampleAfterAGapLongerThanMaxGapStartsAFreshDwell() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)  // last support at 0.125
        harness.feed(0.25, nil)
        let stillAlive = harness.feed(0.375, nil)  // gap exactly maxGap
        #expect(stillAlive.phase == .dwelling(display: a, progress: 0.75))
        // Support returns after 0.375 s without it: too late, so this is a new dwell, not a switch.
        let late = harness.feed(0.5, HandProfile.yawA)
        #expect(late.switchTo == nil)
        #expect(late.phase == .dwelling(display: a, progress: 0))
        #expect(harness.run(from: 0.625, to: 0.875, HandProfile.yawA).allSatisfy { $0.switchTo == nil })
        #expect(harness.feed(1.0, HandProfile.yawA).switchTo == a)
    }

    @Test func noSwitchFiresOnAnUnsupportedSampleEvenAfterTheDwellHasElapsed() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.375, HandProfile.yawA)  // supports through t = 0.375
        let unsupported = harness.feed(0.5, nil)  // dwell elapsed, gap 0.125
        #expect(unsupported.switchTo == nil)
        #expect(unsupported.phase == .dwelling(display: a, progress: 1))
        #expect(harness.feed(0.625, HandProfile.yawA).switchTo == a)
    }

    enum GapSample: CaseIterable, CustomTestStringConvertible {
        case noFace, elsewhere, uncertain, lowConfidence

        var testDescription: String { "\(self)" }

        var expectedReason: SwitchHoldReason {
            switch self {
            case .noFace, .lowConfidence: .noFace
            case .elsewhere: .elsewhere
            case .uncertain: .uncertain
            }
        }

        func feed(_ harness: inout DeciderHarness, at t: Double) -> SwitchDecision {
            switch self {
            case .noFace: harness.feed(t, nil)
            case .elsewhere: harness.feed(t, HandProfile.yawElsewhere)
            case .uncertain: harness.feed(t, HandProfile.yawVeryWeakA)  // margin 0.1, below stay
            case .lowConfidence: harness.feed(t, HandProfile.yawA, confidence: 0.2)
            }
        }
    }

    @Test(arguments: GapSample.allCases)
    func aGapLongerThanMaxGapCancelsTheDwell(gap: GapSample) {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)  // last supporting sample at 0.125
        #expect(gap.feed(&harness, at: 0.25).phase == .dwelling(display: a, progress: 0.5))
        #expect(gap.feed(&harness, at: 0.375).phase == .dwelling(display: a, progress: 0.75))
        let cancelled = gap.feed(&harness, at: 0.5)  // 0.375 s without support > maxGap
        #expect(cancelled.switchTo == nil)
        #expect(cancelled.phase == .idle)
        #expect(cancelled.reason == gap.expectedReason)

        // Looking at A again starts a new dwell; it must not fire on the old clock.
        let restarted = harness.run(from: 0.625, to: 1.125, HandProfile.yawA)
        #expect(restarted[0].phase == .dwelling(display: a, progress: 0))
        #expect(restarted.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(restarted[4].switchTo == a)
    }

    @Test func aHoleInTheStreamStartsAFreshDwellInsteadOfFiring() {
        var harness = DeciderHarness()
        let before = harness.run(from: 0, to: 0.25, HandProfile.yawA)  // dwell running, last support at 0.25
        #expect(before.last?.phase == .dwelling(display: a, progress: 0.5))

        // No samples for 3 s (a camera stall), then a supporting sample. The old dwell's clock (3.25 s) is far past
        // the dwell, but it must not fire: this sample starts a fresh dwell.
        let resumed = harness.run(from: 3.25, to: 3.75, HandProfile.yawA)
        #expect(resumed[0].switchTo == nil)
        #expect(resumed[0].phase == .dwelling(display: a, progress: 0))
        #expect(resumed[0].reason == .dwelling)
        #expect(resumed.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(resumed[4].switchTo == a)  // `dwell` (0.5 s) after the sample that ended the hole
    }

    @Test func aHoleInTheStreamFollowedByANonSupportingSampleEndsTheDwellWithTheIdleReason() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.25, HandProfile.yawA)
        let weak = harness.feed(3.25, HandProfile.yawWeakA)  // margin 0.2: cannot start a dwell
        #expect(weak.phase == .idle)
        #expect(weak.reason == .uncertain)
        // The dwell is gone for good, not merely paused.
        #expect(harness.feed(3.375, HandProfile.yawA).phase == .dwelling(display: a, progress: 0))
    }

    @Test func aHoleInTheStreamFollowedByAConfidentLookElsewhereStartsThatDwell() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.25, HandProfile.yawA)
        let other = harness.feed(3.25, HandProfile.yawC)
        #expect(other.phase == .dwelling(display: c, progress: 0))
    }

    // MARK: Cancellation by focus

    @Test func lookingBackAtTheFocusedDisplayCancelsTheDwell() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)
        let back = harness.feed(0.25, HandProfile.yawB)
        #expect(back.switchTo == nil)
        #expect(back.phase == .idle)
        #expect(back.reason == .alreadyFocused)
        // The old dwell is gone: a return to A restarts the clock.
        #expect(harness.feed(0.375, HandProfile.yawA).phase == .dwelling(display: a, progress: 0))
    }

    @Test func aDwellOnADisplayThatBecomesFocusedIsCancelled() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)
        harness.context.focusedDisplay = a  // for example the user clicked a window on A
        let decision = harness.feed(0.25, HandProfile.yawA)
        #expect(decision.switchTo == nil)
        #expect(decision.phase == .idle)
        #expect(decision.reason == .alreadyFocused)
        harness.context.focusedDisplay = b
        #expect(harness.feed(0.375, HandProfile.yawA).phase == .dwelling(display: a, progress: 0))
    }

    @Test func aConfidentLookAtAnotherDisplayReplacesTheDwell() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)
        let replaced = harness.run(from: 0.25, to: 0.75, HandProfile.yawC)
        #expect(replaced[0].phase == .dwelling(display: c, progress: 0))
        // A's clock would have fired at t = 0.5; C's own clock fires at 0.75.
        #expect(replaced.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(replaced[4].switchTo == c)
    }

    // MARK: Hysteresis

    @Test func aMarginBetweenStayAndEnterCannotStartADwell() {
        var harness = DeciderHarness()
        for decision in harness.run(from: 0, to: 1.5, HandProfile.yawWeakA) {
            #expect(decision.classification.best == a)
            #expect(abs(decision.classification.margin - 0.2) < 1e-12)
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .idle)
            #expect(decision.reason == .uncertain)
        }
    }

    @Test func aMarginBetweenStayAndEnterKeepsAnOngoingDwellAliveAndCanComplete() {
        var harness = DeciderHarness()
        harness.feed(0, HandProfile.yawA)  // starts: margin 1
        let weak = harness.run(from: 0.125, to: 0.5, HandProfile.yawWeakA)
        for (decision, progress) in zip(weak.dropLast(), [0.25, 0.5, 0.75]) {
            #expect(decision.phase == .dwelling(display: a, progress: progress))
            #expect(decision.switchTo == nil)
        }
        #expect(weak[3].switchTo == a)
    }

    @Test func aMarginBelowStayDoesNotSupportTheDwell() {
        var harness = DeciderHarness()
        harness.feed(0, HandProfile.yawA)
        #expect(harness.feed(0.125, HandProfile.yawVeryWeakA).phase == .dwelling(display: a, progress: 0.25))
        #expect(harness.feed(0.25, HandProfile.yawVeryWeakA).phase == .dwelling(display: a, progress: 0.5))
        let dropped = harness.feed(0.375, HandProfile.yawVeryWeakA)  // gap 0.375 > maxGap
        #expect(dropped.phase == .idle)
        #expect(dropped.reason == .uncertain)
    }

    // MARK: Cooldown

    @Test func theCooldownBlocksNewDwellsUntilItEnds() {
        var harness = DeciderHarness()
        let looking = harness.run(from: 0, to: 0.5, HandProfile.yawA)
        #expect(looking[4].switchTo == a)
        harness.context.focusedDisplay = a  // perfect focus

        // Looking at C straight away: blocked until t = 1.25.
        for decision in harness.run(from: 0.625, to: 1.125, HandProfile.yawC) {
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .coolingDown(until: 1.25))
            #expect(decision.reason == .coolingDown)
        }
        // The cooldown ends at t == until, and a dwell starts only then.
        let afterwards = harness.run(from: 1.25, to: 1.75, HandProfile.yawC)
        #expect(afterwards[0].phase == .dwelling(display: c, progress: 0))
        #expect(afterwards.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(afterwards[4].switchTo == c)
    }

    @Test func theCooldownAlsoBlocksWhenThereIsNoFace() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.5, HandProfile.yawA)
        let blocked = harness.feed(0.625, nil)
        #expect(blocked.phase == .coolingDown(until: 1.25))
        #expect(blocked.reason == .coolingDown)
    }

    // MARK: Focus lock

    @Test func focusLockBlocksSwitchingAndCancelsTheDwell() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)
        harness.context.isFocusLocked = true
        for decision in harness.run(from: 0.25, to: 0.75, HandProfile.yawA) {  // 0.5 would have completed it
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .locked)
            #expect(decision.reason == .focusLocked)
            #expect(decision.classification.best == a)  // the classification is still reported
        }
        // Unlocking starts a fresh dwell.
        harness.context.isFocusLocked = false
        let unlocked = harness.run(from: 0.875, to: 1.375, HandProfile.yawA)
        #expect(unlocked[0].phase == .dwelling(display: a, progress: 0))
        #expect(unlocked.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(unlocked[4].switchTo == a)
    }

    @Test func focusLockAlsoClearsTheCooldown() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.5, HandProfile.yawA)  // fires at 0.5, cooldown until 1.25
        harness.context.focusedDisplay = a
        harness.context.isFocusLocked = true
        #expect(harness.feed(0.625, HandProfile.yawC).phase == .locked)
        harness.context.isFocusLocked = false
        // Still before t = 1.25, but the lock reset the machine, so a dwell starts at once.
        #expect(harness.feed(0.75, HandProfile.yawC).phase == .dwelling(display: c, progress: 0))
    }

    // MARK: Targets

    @Test func aNearestDisplayOutsideTheTargetsNeverStartsADwell() {
        var harness = DeciderHarness()
        harness.context.targets = [b, c]
        for decision in harness.run(from: 0, to: 1, HandProfile.yawA) {
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .idle)
            #expect(decision.reason == .notATarget)
        }
        // A target display still works.
        harness.context.focusedDisplay = a
        let toC = harness.run(from: 1.125, to: 1.625, HandProfile.yawC)
        #expect(toC[0].phase == .dwelling(display: c, progress: 0))
        #expect(toC[4].switchTo == c)
    }

    @Test func aDwellDoesNotSurviveItsDisplayLeavingTheTargets() {
        var harness = DeciderHarness()
        harness.run(from: 0, to: 0.125, HandProfile.yawA)
        harness.context.targets = [b, c]
        let first = harness.feed(0.25, HandProfile.yawA)  // treated as a gap: no support, no fire
        #expect(first.switchTo == nil)
        #expect(first.phase == .dwelling(display: a, progress: 0.5))
        harness.feed(0.375, HandProfile.yawA)
        let atDwell = harness.feed(0.5, HandProfile.yawA)  // t - start == dwell, but A is no longer a target
        #expect(atDwell.switchTo == nil)
        #expect(atDwell.phase == .idle)
        #expect(atDwell.reason == .notATarget)
        #expect(harness.feed(0.625, HandProfile.yawA).reason == .notATarget)
    }

    @Test func aTargetRunnerUpDoesNotRescueANonTargetNearestDisplay() {
        var harness = DeciderHarness()
        harness.context.targets = [b]  // only B; the pose is nearest A with B as runner-up
        let decision = harness.feed(0, HandProfile.yawWeakA)
        #expect(decision.classification.runnerUp == b)
        #expect(decision.reason == .notATarget)
    }

    // MARK: Focus state

    @Test func lookingAtTheFocusedDisplayIsAlreadyFocused() {
        var harness = DeciderHarness()
        for decision in harness.run(from: 0, to: 1, HandProfile.yawB) {
            #expect(decision.switchTo == nil)
            #expect(decision.phase == .idle)
            #expect(decision.reason == .alreadyFocused)
        }
    }

    @Test func aNilFocusedDisplayAllowsAnySwitch() {
        var harness = DeciderHarness(focused: nil)
        let first = harness.run(from: 0, to: 0.5, HandProfile.yawB)
        #expect(first[4].switchTo == b)
        // Focus is still unknown. After the cooldown (until 1.25) another look dwells and switches.
        let second = harness.run(from: 0.625, to: 1.75, HandProfile.yawC)
        let fired = second.compactMap(\.switchTo)
        #expect(fired == [c])
        #expect(second.firstIndex { $0.switchTo != nil } == 9)  // t = 1.75: started at 1.25 + 0.5
    }

    // MARK: Idle reasons

    @Test func idleReasonsFollowTheContractOrder() {
        var harness = DeciderHarness()
        #expect(harness.feed(0, nil).reason == .noFace)
        #expect(harness.feed(0.125, HandProfile.yawA, confidence: 0.3).reason == .noFace)
        #expect(harness.feed(0.25, HandProfile.yawElsewhere).reason == .elsewhere)
        #expect(harness.feed(0.375, HandProfile.yawWeakA).reason == .uncertain)

        // Not a target outranks already focused, which outranks uncertain.
        harness.context = SwitchContext(focusedDisplay: a, targets: [b])
        #expect(harness.feed(0.5, HandProfile.yawA).reason == .notATarget)
        harness.context = SwitchContext(focusedDisplay: a)
        #expect(harness.feed(0.625, HandProfile.yawWeakA).reason == .alreadyFocused)
    }

    @Test func everyDecisionCarriesTheClassificationOfItsSample() {
        var harness = DeciderHarness()
        let classifier = PoseClassifier(profile: HandProfile.profile, settings: HandProfile.settings)
        let samples = [
            makeSample(0, yaw: HandProfile.yawA),
            makeSample(0.125, yaw: nil),
            makeSample(0.25, yaw: HandProfile.yawElsewhere),
            makeSample(0.375, yaw: HandProfile.yawWeakA),
        ]
        for sample in samples {
            let decision = harness.machine.process(sample, context: harness.context)
            #expect(decision.classification == classifier.classify(sample.pose))
        }
    }

    // MARK: Time and reset

    @Test func aBackwardsTimestampResetsTheMachine() {
        var harness = DeciderHarness()
        harness.run(from: 10, to: 10.125, HandProfile.yawA)
        // A new stream restarts the clock at 2.0: the dwell begins again instead of continuing.
        let restarted = harness.run(from: 2, to: 2.5, HandProfile.yawA)
        #expect(restarted[0].switchTo == nil)
        #expect(restarted[0].phase == .dwelling(display: a, progress: 0))
        #expect(restarted.dropLast().allSatisfy { $0.switchTo == nil })
        #expect(restarted[4].switchTo == a)
    }

    @Test func aBackwardsTimestampClearsTheCooldown() {
        var harness = DeciderHarness()
        let looking = harness.run(from: 10, to: 10.5, HandProfile.yawA)  // fires; cooldown until 11.25
        #expect(looking[4].switchTo == a)
        harness.context.focusedDisplay = a
        let afterRestart = harness.feed(3, HandProfile.yawC)
        #expect(afterRestart.phase == .dwelling(display: c, progress: 0))
    }

    @Test func anEqualTimestampIsNotBackwards() {
        var harness = DeciderHarness()
        harness.run(from: 1, to: 1.25, HandProfile.yawA)
        let repeated = harness.feed(1.25, HandProfile.yawA)
        #expect(repeated.phase == .dwelling(display: a, progress: 0.5))
    }

    @Test func resetDropsADwell() {
        var harness = DeciderHarness()
        harness.run(from: 5, to: 5.25, HandProfile.yawA)
        harness.machine.reset()
        #expect(harness.feed(5.375, HandProfile.yawA).phase == .dwelling(display: a, progress: 0))
    }

    @Test func resetDropsTheCooldown() {
        var harness = DeciderHarness()
        let looking = harness.run(from: 0, to: 0.5, HandProfile.yawA)
        #expect(looking[4].switchTo == a)
        harness.context.focusedDisplay = a
        harness.machine.reset()
        #expect(harness.feed(0.625, HandProfile.yawC).phase == .dwelling(display: c, progress: 0))
    }

    // MARK: Time tolerance (ε)

    private let epsilon = SwitchStateMachine.timeTolerance

    @Test func epsilonIsOneMicrosecond() {
        #expect(SwitchStateMachine.timeTolerance == 1e-6)
    }

    @Test func aDwellIsCompleteWithinEpsilonBeforeTheDwellButNotMoreThanThat() {
        for (offset, shouldFire) in [(-0.5 * epsilon, true), (-2 * epsilon, false)] {
            var harness = DeciderHarness()
            harness.run(from: 0, to: 0.375, HandProfile.yawA)
            let decision = harness.feed(0.5 + offset, HandProfile.yawA)
            #expect((decision.switchTo == a) == shouldFire)
        }
    }

    @Test func aCooldownIsOverWithinEpsilonBeforeItsEndButNotMoreThanThat() {
        for (offset, blocked) in [(-0.5 * epsilon, false), (-2 * epsilon, true)] {
            var harness = DeciderHarness()
            harness.run(from: 0, to: 0.5, HandProfile.yawA)  // fires at 0.5, cooldown until 1.25
            harness.context.focusedDisplay = a
            let decision = harness.feed(1.25 + offset, HandProfile.yawC)
            #expect((decision.reason == .coolingDown) == blocked)
            #expect((decision.phase == .dwelling(display: c, progress: 0)) == !blocked)
        }
    }

    @Test func aGapIsExceededOnlyBeyondMaxGapPlusEpsilon() {
        for (offset, survives) in [(0.5 * epsilon, true), (2 * epsilon, false)] {
            var harness = DeciderHarness()
            harness.run(from: 0, to: 0.125, HandProfile.yawA)  // last support at 0.125
            harness.feed(0.25, nil)
            let decision = harness.feed(0.125 + 0.25 + offset, nil)  // gap = maxGap + offset
            #expect((decision.reason == .dwelling) == survives)
            #expect((decision.phase == .idle) == !survives)
        }
    }

    // MARK: Zero dwell

    @Test func aDwellOfZeroFiresImmediately() {
        var settings = HandProfile.settings
        settings.dwell = 0
        var harness = DeciderHarness(settings: settings)
        let fired = harness.feed(0, HandProfile.yawA)
        #expect(fired.switchTo == a)
        #expect(fired.phase == .coolingDown(until: 0.75))
        #expect(fired.reason == nil)
    }

    @Test func aDwellOfZeroStillNeedsTheEnterMarginAndRespectsTheCooldown() {
        var settings = HandProfile.settings
        settings.dwell = 0
        var harness = DeciderHarness(settings: settings)
        #expect(harness.feed(0, HandProfile.yawWeakA).switchTo == nil)  // margin 0.2 < enter
        #expect(harness.feed(0.125, HandProfile.yawA).switchTo == a)
        harness.context.focusedDisplay = a
        let blocked = harness.run(from: 0.25, to: 0.75, HandProfile.yawC)
        #expect(blocked.allSatisfy { $0.switchTo == nil && $0.reason == .coolingDown })
        #expect(harness.feed(0.875, HandProfile.yawC).switchTo == c)  // cooldown over (until 0.875): fires at once
    }
}
