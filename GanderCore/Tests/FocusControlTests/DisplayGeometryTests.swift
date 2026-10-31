import CoreGraphics
import GanderModels
import Testing

@testable import FocusControl

@Suite struct DisplayGeometryTests {
    // Main display 1440x900 at the AppKit origin. Quartz H is 900.
    private let main = FocusFixtures.display(
        "main", appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMain: true)

    // MARK: AppKit to Quartz

    @Test func mainDisplayKeepsItsFrame() {
        let layout = DisplayLayout(displays: [main])
        #expect(
            DisplayGeometry.quartzFrames(for: layout).map(\.frame) == [CGRect(x: 0, y: 0, width: 1440, height: 900)])
    }

    @Test func displayToTheRightKeepsXAndFlipsY() {
        // AppKit: bottom edge 0, top edge 1080 -> Quartz top is 900 - 1080 = -180.
        let right = FocusFixtures.display("right", appKitFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [main, right]))
        #expect(frames.first { $0.id == "right" }?.frame == CGRect(x: 1440, y: -180, width: 1920, height: 1080))
    }

    @Test func displayToTheLeftHasNegativeX() {
        // AppKit y -100..980 -> Quartz y = 900 - 980 = -80.
        let left = FocusFixtures.display("left", appKitFrame: CGRect(x: -1920, y: -100, width: 1920, height: 1080))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [main, left]))
        #expect(frames.first { $0.id == "left" }?.frame == CGRect(x: -1920, y: -80, width: 1920, height: 1080))
    }

    @Test func displayAboveHasNegativeQuartzY() {
        // AppKit y 900..1800 -> Quartz y = 900 - 1800 = -900.
        let above = FocusFixtures.display("above", appKitFrame: CGRect(x: 0, y: 900, width: 1440, height: 900))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [main, above]))
        #expect(frames.first { $0.id == "above" }?.frame == CGRect(x: 0, y: -900, width: 1440, height: 900))
    }

    @Test func displayBelowHasPositiveQuartzY() {
        // AppKit y -1080..0 -> Quartz y = 900 - 0 = 900.
        let below = FocusFixtures.display("below", appKitFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [main, below]))
        #expect(frames.first { $0.id == "below" }?.frame == CGRect(x: 0, y: 900, width: 1920, height: 1080))
    }

    @Test func conversionUsesTheHeightOfTheDisplayAtTheOriginEvenIfNotFlaggedMain() {
        let atOrigin = FocusFixtures.display("a", appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let flaggedMain = FocusFixtures.display(
            "b",
            appKitFrame: CGRect(x: 1000, y: 0, width: 1000, height: 1200),
            isMain: true
        )
        #expect(DisplayGeometry.referenceHeight(for: [atOrigin, flaggedMain]) == 700)
    }

    @Test func referenceHeightFallsBackToTheMainDisplayThenTheFirst() {
        let first = FocusFixtures.display("a", appKitFrame: CGRect(x: 10, y: 10, width: 1000, height: 700))
        let main = FocusFixtures.display(
            "b", appKitFrame: CGRect(x: 1010, y: 0, width: 1000, height: 1200), isMain: true)
        #expect(DisplayGeometry.referenceHeight(for: [first, main]) == 1200)
        let plain = FocusFixtures.display("c", appKitFrame: CGRect(x: 1010, y: 0, width: 1000, height: 1300))
        #expect(DisplayGeometry.referenceHeight(for: [first, plain]) == 700)
    }

    @Test func emptyLayoutHasNoDisplays() {
        #expect(DisplayGeometry.referenceHeight(for: []) == nil)
        #expect(DisplayGeometry.quartzFrames(for: .empty).isEmpty)
    }

    @Test func layoutOrderIsPreserved() {
        let right = FocusFixtures.display("right", appKitFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [right, main]))
        #expect(frames.map(\.id) == ["main", "right"])
    }

    // MARK: Display assignment

    private let left = FocusFixtures.quartz("L", CGRect(x: 0, y: 0, width: 1000, height: 1000))
    private let right = FocusFixtures.quartz("R", CGRect(x: 1000, y: 0, width: 1000, height: 1000))

    @Test func windowInsideOneDisplayIsAssignedToIt() {
        let bounds = CGRect(x: 1100, y: 100, width: 300, height: 300)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, right]) == "R")
    }

    @Test func largestOverlapWinsForAStraddlingWindow() {
        // 300 pt of the window on L, 100 pt on R.
        let bounds = CGRect(x: 700, y: 100, width: 400, height: 300)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, right]) == "L")
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [right, left]) == "L")
    }

    @Test func tieGoesToTheDisplayContainingTheCenter() {
        // Different heights make equal overlap areas with the center on the left display.
        let shortLeft = FocusFixtures.quartz("L", CGRect(x: 0, y: 0, width: 1000, height: 200))
        let tallRight = FocusFixtures.quartz("R", CGRect(x: 1000, y: 0, width: 1000, height: 300))
        // Overlaps: L 300x200 = 60000, R 200x300 = 60000. Center (950, 190) is on L.
        let bounds = CGRect(x: 700, y: 0, width: 500, height: 380)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [shortLeft, tallRight]) == "L")
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [tallRight, shortLeft]) == "L")
    }

    @Test func tieOnTheSharedEdgeGoesToTheDisplayHoldingTheCenterPoint() {
        let bounds = CGRect(x: 900, y: 100, width: 200, height: 200)
        // Center (1000, 200) lies on R's left edge, which R contains.
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, right]) == "R")
    }

    @Test func tieWithTheCenterOnNoDisplayGoesToTheFirstInLayoutOrder() {
        let farRight = FocusFixtures.quartz("R", CGRect(x: 1200, y: 0, width: 1000, height: 1000))
        // Overlaps 100x100 on each; the center (1100, 50) is in the gap.
        let bounds = CGRect(x: 900, y: 0, width: 400, height: 100)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, farRight]) == "L")
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [farRight, left]) == "R")
    }

    @Test func windowOverlappingNoDisplayIsSkipped() {
        let bounds = CGRect(x: 5000, y: 5000, width: 300, height: 300)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, right]) == nil)
    }

    @Test func windowTouchingOnlyAnEdgeIsSkipped() {
        let bounds = CGRect(x: 2000, y: 0, width: 300, height: 300)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: [left, right]) == nil)
    }

    @Test func noDisplaysMeansNoAssignment() {
        #expect(DisplayGeometry.assignedDisplay(for: CGRect(x: 0, y: 0, width: 300, height: 300), in: []) == nil)
    }

    @Test func windowOnADisplayAboveTheMainDisplayIsAssignedThroughConversion() {
        let above = FocusFixtures.display("above", appKitFrame: CGRect(x: 0, y: 900, width: 1440, height: 900))
        let frames = DisplayGeometry.quartzFrames(for: DisplayLayout(displays: [main, above]))
        // Quartz y of the upper display is -900..0.
        let bounds = CGRect(x: 100, y: -500, width: 600, height: 400)
        #expect(DisplayGeometry.assignedDisplay(for: bounds, in: frames) == "above")
    }
}
