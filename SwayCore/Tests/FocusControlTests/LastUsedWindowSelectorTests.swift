import CoreGraphics
import SwayModels
import Testing

@testable import FocusControl

@Suite struct LastUsedWindowSelectorTests {
    private let ownPID: Int32 = 999
    private let displays = [
        FocusFixtures.quartz("L", CGRect(x: 0, y: 0, width: 1000, height: 800)),
        FocusFixtures.quartz("R", CGRect(x: 1000, y: 0, width: 1000, height: 800)),
    ]

    private func onLeft(number: UInt32, pid: Int32 = 1, layer: Int = 0) -> WindowRecord {
        FocusFixtures.record(
            number: number,
            processID: pid,
            layer: layer,
            bounds: CGRect(x: 100, y: 100, width: 500, height: 400)
        )
    }

    private func onRight(number: UInt32, pid: Int32 = 2, layer: Int = 0) -> WindowRecord {
        FocusFixtures.record(
            number: number,
            processID: pid,
            layer: layer,
            bounds: CGRect(x: 1100, y: 100, width: 500, height: 400)
        )
    }

    private func select(_ records: [WindowRecord]) -> [DisplayID: WindowRecord] {
        LastUsedWindowSelector.select(from: records, displays: displays, ownProcessID: ownPID)
    }

    @Test func frontmostNormalWindowOnEachDisplayWins() {
        let result = select([onRight(number: 10), onLeft(number: 11), onLeft(number: 12), onRight(number: 13)])
        #expect(result["L"]?.number == 11)
        #expect(result["R"]?.number == 10)
    }

    @Test func ownWindowsAreExcludedSoTheNextOneWins() {
        let result = select([onLeft(number: 1, pid: ownPID), onLeft(number: 2, pid: 5)])
        #expect(result["L"]?.number == 2)
    }

    @Test func displayWithOnlyOwnWindowsIsAbsent() {
        let result = select([onRight(number: 1, pid: ownPID), onLeft(number: 2)])
        #expect(result["R"] == nil)
        #expect(result["L"]?.number == 2)
    }

    @Test func displaysWithoutWindowsAreAbsent() {
        #expect(select([onLeft(number: 1)]).keys.sorted { $0.rawValue < $1.rawValue } == ["L"])
        #expect(select([]).isEmpty)
    }

    @Test func nonNormalWindowsAreSkipped() {
        let menuBarLike = onLeft(number: 1, layer: 25)
        let tiny = FocusFixtures.record(number: 2, bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        let dock = FocusFixtures.record(
            number: 3, ownerName: "Dock", bounds: CGRect(x: 0, y: 0, width: 900, height: 700))
        let result = select([menuBarLike, tiny, dock, onLeft(number: 4)])
        #expect(result["L"]?.number == 4)
    }

    @Test func windowsOffEveryDisplayAreSkipped() {
        let offscreen = FocusFixtures.record(number: 1, bounds: CGRect(x: 9000, y: 9000, width: 500, height: 400))
        #expect(select([offscreen, onRight(number: 2)]).keys.map(\.rawValue) == ["R"])
    }

    @Test func straddlingWindowCountsForTheDisplayWithMostOfIt() {
        let straddling = FocusFixtures.record(number: 1, bounds: CGRect(x: 600, y: 100, width: 500, height: 400))
        let result = select([straddling])
        #expect(result["L"]?.number == 1)
        #expect(result["R"] == nil)
    }

    @Test func noDisplaysSelectsNothing() {
        let result = LastUsedWindowSelector.select(from: [onLeft(number: 1)], displays: [], ownProcessID: ownPID)
        #expect(result.isEmpty)
    }

    // MARK: Frontmost window of one app

    @Test func frontmostWindowOfAProcessIsItsTopmostNormalOne() {
        let records = [onLeft(number: 1, pid: 7, layer: 3), onRight(number: 2, pid: 8), onRight(number: 3, pid: 7)]
        let found = LastUsedWindowSelector.frontmostWindow(
            ofProcess: 7,
            in: records,
            displays: displays,
            ownProcessID: ownPID
        )
        #expect(found?.record.number == 3)
        #expect(found?.displayID == "R")
    }

    @Test func frontmostWindowOfAProcessWithoutWindowsIsNil() {
        let found = LastUsedWindowSelector.frontmostWindow(
            ofProcess: 42,
            in: [onLeft(number: 1)],
            displays: displays,
            ownProcessID: ownPID
        )
        #expect(found == nil)
    }
}
