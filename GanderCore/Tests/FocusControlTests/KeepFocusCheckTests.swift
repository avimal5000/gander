import CoreGraphics
import GanderModels
import Testing

@testable import FocusControl

@Suite struct KeepFocusCheckTests {
    private let displays = [
        FocusFixtures.quartz("L", CGRect(x: 0, y: 0, width: 1000, height: 800)),
        FocusFixtures.quartz("R", CGRect(x: 1000, y: 0, width: 1000, height: 800)),
    ]

    private func left(_ frame: CGRect?) -> Bool {
        KeepFocusCheck.focusLeftDisplay("L", focusedFrame: frame, displays: displays)
    }

    @Test func focusOnAWindowOnAnotherDisplayIsPutBack() {
        #expect(left(CGRect(x: 1100, y: 100, width: 500, height: 400)))
    }

    @Test func aNewWindowOnTheSameDisplayKeepsFocus() {
        #expect(!left(CGRect(x: 130, y: 130, width: 500, height: 400)))
    }

    @Test func aWindowMostlyOnTheTargetDisplayStaysEvenWhenItStraddles() {
        #expect(!left(CGRect(x: 600, y: 100, width: 500, height: 400)))
        #expect(left(CGRect(x: 900, y: 100, width: 500, height: 400)))
    }

    @Test func anUnknownFrameOrOneOnNoDisplayChangesNothing() {
        #expect(!left(nil))
        #expect(!left(CGRect(x: 5000, y: 5000, width: 500, height: 400)))
    }
}
