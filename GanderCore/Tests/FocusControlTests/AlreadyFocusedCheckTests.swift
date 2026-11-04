import CoreGraphics
import GanderModels
import Testing

@testable import FocusControl

@Suite struct AlreadyFocusedCheckTests {
    private let ownPID: Int32 = 999
    private let frontPID: Int32 = 1
    private let displays = [
        FocusFixtures.quartz("L", CGRect(x: 0, y: 0, width: 1000, height: 800)),
        FocusFixtures.quartz("R", CGRect(x: 1000, y: 0, width: 1000, height: 800)),
    ]
    private let leftBounds = CGRect(x: 100, y: 100, width: 500, height: 400)
    private let rightBounds = CGRect(x: 1100, y: 100, width: 500, height: 400)

    private func check(
        _ display: DisplayID, focusedFrame: CGRect?, _ records: [WindowRecord], processID: Int32? = nil
    ) -> WindowRecord? {
        AlreadyFocusedCheck.focusedRecord(
            on: display, processID: processID ?? frontPID, focusedFrame: focusedFrame, in: records,
            displays: displays, ownProcessID: ownPID)
    }

    @Test func theFocusedWindowOnTheTargetDisplayIsFound() {
        let focused = FocusFixtures.record(number: 1, processID: frontPID, bounds: leftBounds)
        let behind = FocusFixtures.record(number: 2, processID: 2, bounds: leftBounds)
        #expect(check("L", focusedFrame: leftBounds, [focused, behind])?.number == 1)
    }

    @Test func theFocusedWindowOnAnotherDisplayIsNot() {
        let focused = FocusFixtures.record(number: 1, processID: frontPID, bounds: rightBounds)
        let left = FocusFixtures.record(number: 2, processID: 2, bounds: leftBounds)
        #expect(check("L", focusedFrame: rightBounds, [focused, left]) == nil)
    }

    @Test func aStraddlingWindowCountsOnTheDisplayWithTheSmallerPartWhenThatPartIsLarge() {
        // 700 of 1000 pt wide on R, 300 on L: assigned to R, but it covers 300×800 of L's 1000×800, 30 %.
        let straddling = CGRect(x: 700, y: 0, width: 1000, height: 800)
        let focused = FocusFixtures.record(number: 1, processID: frontPID, bounds: straddling)
        let buried = FocusFixtures.record(number: 2, processID: 2, bounds: leftBounds)
        #expect(check("L", focusedFrame: straddling, [focused, buried])?.number == 1)
        #expect(check("R", focusedFrame: straddling, [focused, buried])?.number == 1)
    }

    @Test func aSliverOnTheTargetDisplayDoesNotCount() {
        // 100 × 400 on L: 5 % of it.
        let sliver = CGRect(x: 900, y: 100, width: 600, height: 400)
        let focused = FocusFixtures.record(number: 1, processID: frontPID, bounds: sliver)
        #expect(check("L", focusedFrame: sliver, [focused]) == nil)
    }

    @Test func theFocusedWindowIsMatchedByFrameNotByZOrder() {
        let other = FocusFixtures.record(number: 1, processID: frontPID, bounds: rightBounds)
        let focused = FocusFixtures.record(number: 2, processID: frontPID, bounds: leftBounds)
        #expect(check("L", focusedFrame: leftBounds.offsetBy(dx: 1, dy: 1), [other, focused])?.number == 2)
        #expect(check("R", focusedFrame: leftBounds, [other, focused]) == nil)
    }

    @Test func withoutAReadableOrMatchingFrameTheAppsFrontmostNormalWindowStandsIn() {
        let tiny = FocusFixtures.record(
            number: 1, processID: frontPID, bounds: CGRect(x: 10, y: 10, width: 40, height: 40))
        let front = FocusFixtures.record(number: 2, processID: frontPID, bounds: leftBounds)
        let sheet = CGRect(x: 200, y: 120, width: 300, height: 200)
        #expect(check("L", focusedFrame: nil, [tiny, front])?.number == 2)
        #expect(check("L", focusedFrame: sheet, [tiny, front])?.number == 2)
    }

    @Test func aStandInThatAnotherAppCoversIsNotTheWindowInUse() {
        // Finder with the desktop clicked: frontmost, no focused window, its only window buried under the browser.
        let cover = FocusFixtures.record(number: 1, processID: 2, bounds: leftBounds)
        let buried = FocusFixtures.record(number: 2, processID: frontPID, bounds: leftBounds)
        #expect(check("L", focusedFrame: nil, [cover, buried]) == nil)
        #expect(check("L", focusedFrame: nil, [buried, cover])?.number == 2)
    }

    @Test func aMatchedFocusedWindowCountsEvenWhenAnotherAppCoversIt() {
        let cover = FocusFixtures.record(number: 1, processID: 2, bounds: leftBounds)
        let focused = FocusFixtures.record(number: 2, processID: frontPID, bounds: leftBounds)
        #expect(check("L", focusedFrame: leftBounds, [cover, focused])?.number == 2)
    }

    @Test func nothingIsFoundForGanderItselfAnAppWithoutWindowsOrAnUnknownDisplay() {
        let own = FocusFixtures.record(number: 1, processID: ownPID, bounds: leftBounds)
        let other = FocusFixtures.record(number: 2, processID: 2, bounds: leftBounds)
        #expect(check("L", focusedFrame: leftBounds, [own], processID: ownPID) == nil)
        #expect(check("L", focusedFrame: nil, [other]) == nil)
        let front = FocusFixtures.record(processID: frontPID, bounds: leftBounds)
        #expect(check("X", focusedFrame: leftBounds, [front]) == nil)
    }
}
