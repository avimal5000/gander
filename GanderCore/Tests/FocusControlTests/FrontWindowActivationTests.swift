import FrontProcess
import Testing

@testable import FocusControl

@Suite struct FrontWindowActivationTests {
    /// unimpErr: what `GanderFrontWindowOnly` returns when macOS no longer has the Carbon calls.
    private let callsMissing: Int32 = -4

    @Test func anAcceptedRequestThatBringsTheAppForwardNeedsNoFallback() async {
        var fallbacks = 0
        let outcome = await FrontWindowActivation.run(
            frontWindowOnly: { 0 },
            becomesFrontmost: { true },
            fallback: {
                fallbacks += 1
                return true
            }
        )
        #expect(outcome == .frontWindowOnly)
        #expect(fallbacks == 0)
    }

    @Test func missingCallsFallBackWithoutWaiting() async {
        var waits = 0
        let outcome = await FrontWindowActivation.run(
            frontWindowOnly: { callsMissing },
            becomesFrontmost: {
                waits += 1
                return true
            },
            fallback: { true }
        )
        #expect(outcome == .fellBack(status: callsMissing, requested: true))
        #expect(waits == 0)
    }

    @Test func anAcceptedRequestThatLeavesTheAppBehindFallsBack() async {
        let outcome = await FrontWindowActivation.run(
            frontWindowOnly: { 0 },
            becomesFrontmost: { false },
            fallback: { false }
        )
        #expect(outcome == .fellBack(status: 0, requested: false))
    }

    @Test func aRequestCancelledWhileWaitingAsksForNothingMore() async {
        var fallbacks = 0
        let outcome = await FrontWindowActivation.run(
            frontWindowOnly: { 0 },
            becomesFrontmost: {
                withUnsafeCurrentTask { $0?.cancel() }
                return false
            },
            fallback: {
                fallbacks += 1
                return true
            }
        )
        #expect(outcome == .cancelled)
        #expect(fallbacks == 0)
    }

    /// The real C call with a process that cannot exist: it resolves and refuses, and no focus moves.
    @Test func theRealCallRefusesAnUnknownProcess() {
        #expect(GanderFrontWindowOnly(Int32.max) != 0)
    }
}
