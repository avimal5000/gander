import Foundation
import SwayModels
import Testing

@testable import SwayUI

@Suite("Tracking loop")
struct TrackingLoopTests {
    private let left = Fixtures.left.id
    private let right = Fixtures.right.id
    private let far = Fixtures.far.id

    private var focused: FocusResult {
        .focused(Fixtures.window(on: Fixtures.right), method: .appActivation, milliseconds: 50)
    }

    private func look(at display: DisplayID, margin: Double = 0.6) -> PoseClassification {
        Fixtures.classification(best: display, margin: margin)
    }

    // MARK: Focused display

    @Test func nothingIsKnownAtFirst() {
        let loop = TrackingLoop()
        #expect(loop.focusedDisplay == nil)
        #expect(!loop.isFocusing)
        #expect(loop.epoch == 0)
    }

    @Test func theFocusedDisplayPrefersTheRequestInFlightThenTheOverrideThenThePoll() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        #expect(loop.focusedDisplay == left)

        loop.beginAttempt(right)
        #expect(loop.focusedDisplay == right, "The request in flight")
        #expect(loop.isFocusing)

        loop.finishAttempt(right, result: .noWindow(right))
        #expect(loop.focusedDisplay == right, "The override")
        #expect(!loop.isFocusing)
        #expect(loop.polled == left)
    }

    // MARK: Attempts

    @Test func beginAttemptRemembersTheFocusAsItWasAndCountsAnEpoch() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        let epoch = loop.epoch

        let began = loop.beginAttempt(right)

        #expect(began)
        #expect(loop.inFlight == right)
        #expect(loop.epoch == epoch + 1)
        loop.finishAttempt(right, result: .failed(nil, reason: "x"))
        #expect(loop.override == TrackingLoop.Override(display: right, before: left))
    }

    @Test func onlyOneAttemptRunsAtATime() {
        var loop = TrackingLoop()
        let first = loop.beginAttempt(left)
        let epoch = loop.epoch

        let second = loop.beginAttempt(right)

        #expect(first)
        #expect(!second)
        #expect(loop.inFlight == left, "Unchanged")
        #expect(loop.epoch == epoch)
    }

    @Test func aFocusedResultMakesTheTargetTheFocusAndClearsTheOverride() {
        var loop = TrackingLoop()
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))
        #expect(loop.override != nil)

        loop.beginAttempt(left)
        loop.finishAttempt(left, result: focused)

        #expect(loop.polled == left)
        #expect(loop.override == nil)
        #expect(loop.focusedDisplay == left)
        #expect(!loop.isFocusing)
    }

    @Test func aNoWindowOrFailedResultTreatsTheTargetAsFocusedUntilFocusMoves() {
        for result in [FocusResult.noWindow(right), .failed(nil, reason: "Focus did not move")] {
            var loop = TrackingLoop()
            loop.pollFinished(left, epoch: loop.pollStarted())
            loop.beginAttempt(right)
            loop.finishAttempt(right, result: result)

            #expect(loop.focusedDisplay == right)
            #expect(loop.polled == left, "The real focus is still known")
        }
    }

    @Test func aNotTrustedResultChangesNothingElse() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)

        loop.finishAttempt(right, result: .notTrusted)

        #expect(loop.polled == left)
        #expect(loop.override == nil)
        #expect(loop.inFlight == nil)
        #expect(loop.focusedDisplay == left)
    }

    @Test func finishingCountsAnotherEpoch() {
        var loop = TrackingLoop()
        loop.beginAttempt(right)
        let epoch = loop.epoch
        loop.finishAttempt(right, result: .notTrusted)
        #expect(loop.epoch == epoch + 1)
    }

    // MARK: Polls

    @Test func aPollResultBecomesTheFocusWithoutAnOverride() {
        var loop = TrackingLoop()
        loop.pollFinished(right, epoch: loop.pollStarted())
        #expect(loop.polled == right)

        loop.pollFinished(nil, epoch: loop.pollStarted())
        #expect(loop.polled == nil, "Unknown is a result too")
    }

    @Test func aPollThatStartedBeforeAnAttemptIsIgnoredAfterIt() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        let stale = loop.pollStarted()

        loop.beginAttempt(right)
        loop.finishAttempt(right, result: focused)
        loop.pollFinished(left, epoch: stale)

        #expect(loop.polled == right, "The answer from before the switch must not undo it")
    }

    @Test func aPollThatFinishesWhileAnAttemptIsInFlightIsIgnored() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        let during = loop.pollStarted()

        loop.pollFinished(far, epoch: during)

        #expect(loop.polled == left)
    }

    @Test func aPollThatStartedBeforeAResetIsIgnored() {
        var loop = TrackingLoop()
        let stale = loop.pollStarted()
        loop.reset()
        loop.pollFinished(right, epoch: stale)
        #expect(loop.polled == nil)
    }

    @Test func anOverrideSurvivesAPollThatStillSaysWhatFocusWasBefore() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))

        loop.pollFinished(left, epoch: loop.pollStarted())

        #expect(loop.override == TrackingLoop.Override(display: right, before: left))
        #expect(loop.focusedDisplay == right, "That focus is already known")
    }

    @Test func anOverrideSurvivesAnUnknownPollWhenFocusWasUnknownBefore() {
        var loop = TrackingLoop()
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))

        loop.pollFinished(nil, epoch: loop.pollStarted())

        #expect(loop.focusedDisplay == right)
    }

    @Test func aPollThatSaysSomethingElseClearsTheOverride() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))

        loop.pollFinished(far, epoch: loop.pollStarted())

        #expect(loop.override == nil)
        #expect(loop.polled == far)
        #expect(loop.focusedDisplay == far)
    }

    // MARK: The look

    @Test func aConfidentLookAtAnotherDisplayClearsTheOverride() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))

        loop.lookChanged(to: look(at: left), enterMargin: 0.3)

        #expect(loop.override == nil)
        #expect(loop.focusedDisplay == left)
    }

    @Test func theOverridesOwnDisplayAWeakLookAndOtherKindsOfLookKeepTheOverride() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))
        let kept = loop

        loop.lookChanged(to: look(at: right), enterMargin: 0.3)
        #expect(loop == kept, "Still looking at the same display")
        loop.lookChanged(to: look(at: left, margin: 0.29), enterMargin: 0.3)
        #expect(loop == kept, "Not confident enough yet")
        loop.lookChanged(to: Fixtures.classification(.elsewhere), enterMargin: 0.3)
        #expect(loop == kept)
        loop.lookChanged(to: .noFace, enterMargin: 0.3)
        #expect(loop == kept)
    }

    @Test func aMarginExactlyAtTheEnterMarginCounts() {
        var loop = TrackingLoop()
        loop.beginAttempt(right)
        loop.finishAttempt(right, result: .noWindow(right))

        loop.lookChanged(to: look(at: left, margin: 0.3), enterMargin: 0.3)

        #expect(loop.override == nil)
    }

    @Test func aLookChangeWithoutAnOverrideChangesNothing() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        let before = loop
        loop.lookChanged(to: look(at: right), enterMargin: 0.3)
        #expect(loop == before)
    }

    // MARK: Reset

    @Test func resetClearsEverythingAndCountsAnEpoch() {
        var loop = TrackingLoop()
        loop.pollFinished(left, epoch: loop.pollStarted())
        loop.beginAttempt(right)
        let epoch = loop.epoch

        loop.reset()

        #expect(loop.polled == nil)
        #expect(loop.override == nil)
        #expect(loop.inFlight == nil)
        #expect(loop.focusedDisplay == nil)
        #expect(loop.epoch == epoch + 1)
        let began = loop.beginAttempt(left)
        #expect(began, "A new attempt may start")
    }

    // MARK: Targets (SPEC D22)

    @Test func allCalibratedDisplaysAreTargetsUpToTheLimit() {
        let two = Fixtures.profile(layout: Fixtures.twoDisplays)
        let three = Fixtures.profile(layout: Fixtures.threeDisplays)
        #expect(TrackingLoop.targets(layout: Fixtures.twoDisplays, profile: two, limit: 3) == nil)
        #expect(TrackingLoop.targets(layout: Fixtures.threeDisplays, profile: three, limit: 3) == nil)
    }

    @Test func aFourthDisplayIsNotATarget() {
        let four = Fixtures.profile(layout: Fixtures.fourDisplays)
        let targets = TrackingLoop.targets(layout: Fixtures.fourDisplays, profile: four, limit: 3)
        #expect(targets == [Fixtures.left.id, Fixtures.right.id, Fixtures.far.id])
    }

    @Test func targetsFollowLayoutOrderAndSkipUncalibratedDisplays() {
        // The profile has Right, Far, and Extra but not Left: the first 3 calibrated displays in layout order.
        let profile = Fixtures.profile(layout: DisplayLayout(displays: [Fixtures.right, Fixtures.far, Fixtures.extra]))
        let targets = TrackingLoop.targets(layout: Fixtures.fourDisplays, profile: profile, limit: 2)
        #expect(targets == [Fixtures.right.id, Fixtures.far.id])
    }
}
