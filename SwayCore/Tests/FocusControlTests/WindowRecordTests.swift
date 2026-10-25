import CoreGraphics
import Foundation
import Testing

@testable import FocusControl

@Suite struct WindowRecordTests {
    @Test func parsesAllFields() {
        let bounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        let record = WindowRecord(
            entry: FocusFixtures.entry(
                number: 42,
                processID: 777,
                ownerName: "Safari",
                layer: 0,
                bounds: bounds,
                alpha: 0.5
            )
        )
        #expect(
            record
                == WindowRecord(
                    number: 42,
                    processID: 777,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: bounds,
                    alpha: 0.5
                )
        )
    }

    @Test func parsesBoundsGivenAsPlainDictionary() {
        var entry = FocusFixtures.entry()
        entry[kCGWindowBounds as String] = ["X": 5, "Y": 6, "Width": 700, "Height": 500] as [String: Any]
        #expect(WindowRecord(entry: entry)?.bounds == CGRect(x: 5, y: 6, width: 700, height: 500))
    }

    @Test func parsesNegativeOriginsFromDisplaysLeftOfOrAboveTheMainDisplay() {
        let bounds = CGRect(x: -1920, y: -300, width: 1000, height: 700)
        #expect(WindowRecord(entry: FocusFixtures.entry(bounds: bounds))?.bounds == bounds)
    }

    @Test func missingNumberSkipsTheEntry() {
        #expect(WindowRecord(entry: FocusFixtures.entry(number: nil)) == nil)
    }

    @Test func missingProcessIDSkipsTheEntry() {
        #expect(WindowRecord(entry: FocusFixtures.entry(processID: nil)) == nil)
    }

    @Test func missingBoundsSkipsTheEntry() {
        #expect(WindowRecord(entry: FocusFixtures.entry(bounds: nil)) == nil)
    }

    @Test func malformedValuesSkipTheEntry() {
        var wrongNumberType = FocusFixtures.entry()
        wrongNumberType[kCGWindowNumber as String] = "7"
        var negativeNumber = FocusFixtures.entry()
        negativeNumber[kCGWindowNumber as String] = -1
        var hugePID = FocusFixtures.entry()
        hugePID[kCGWindowOwnerPID as String] = Int64(Int32.max) + 1
        var badBounds = FocusFixtures.entry()
        badBounds[kCGWindowBounds as String] = ["X": 1] as [String: Any]
        var nonDictionaryBounds = FocusFixtures.entry()
        nonDictionaryBounds[kCGWindowBounds as String] = "nope"

        #expect(WindowRecord(entry: wrongNumberType) == nil)
        #expect(WindowRecord(entry: negativeNumber) == nil)
        #expect(WindowRecord(entry: hugePID) == nil)
        #expect(WindowRecord(entry: badBounds) == nil)
        #expect(WindowRecord(entry: nonDictionaryBounds) == nil)
    }

    @Test func missingOwnerNameBecomesEmpty() {
        #expect(WindowRecord(entry: FocusFixtures.entry(ownerName: nil))?.ownerName == "")
    }

    @Test func missingAlphaDefaultsToOne() {
        #expect(WindowRecord(entry: FocusFixtures.entry(alpha: nil))?.alpha == 1)
    }

    @Test func missingLayerDefaultsToTheNormalLayer() {
        #expect(WindowRecord(entry: FocusFixtures.entry(layer: nil))?.layer == 0)
    }

    @Test func integerAlphaIsAccepted() {
        var entry = FocusFixtures.entry()
        entry[kCGWindowAlpha as String] = 1
        #expect(WindowRecord(entry: entry)?.alpha == 1)
    }

    @Test func parseKeepsFrontToBackOrderAndDropsUnusableEntries() {
        let records = WindowRecord.parse([
            FocusFixtures.entry(number: 3),
            FocusFixtures.entry(number: nil),
            FocusFixtures.entry(number: 1),
            FocusFixtures.entry(number: 2, bounds: nil),
            FocusFixtures.entry(number: 9),
        ])
        #expect(records.map(\.number) == [3, 1, 9])
    }

    @Test func parseOfAnEmptyListIsEmpty() {
        #expect(WindowRecord.parse([]).isEmpty)
    }

    /// Reads the real window list. It needs no permission and may be empty on a headless runner.
    @Test func windowServerListReturnsWithoutCrashing() {
        let records = WindowServerList.currentRecords()
        for record in records {
            #expect(record.processID > 0)
        }
    }
}
