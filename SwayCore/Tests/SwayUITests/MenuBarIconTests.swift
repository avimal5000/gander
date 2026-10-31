import AppKit
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("Menu bar glyph and icon")
struct MenuBarIconTests {
    // MARK: Mapping (SPEC F25)

    @Test func everyStatusMapsToTheGlyphTheTableSays() {
        let rows: [(TrackingStatus, MenuBarGlyph)] = [
            (.tracking, .tracking), (.noFace, .tracking), (.calibrating, .tracking), (.starting, .tracking),
            (.paused, .paused), (.oneDisplay, .paused), (.suspended(.screenLocked), .paused),
            (.suspended(.systemSleep), .paused), (.suspended(.displaysAsleep), .paused),
            (.focusLock, .focusLock),
            (.cameraBlocked, .attention), (.cameraFailed, .attention),
            (.cameraBusy("in use by another app"), .attention),
            (.cameraBusy("Camera disconnected"), .attention), (.needsCalibration, .attention),
            (.needsAccessibility, .attention),
        ]
        for (status, glyph) in rows {
            #expect(MenuBarGlyph(status) == glyph, "\(status)")
        }
    }

    @Test func theTableCoversEveryStatusCase() {
        // One representative per case: a new case breaks the switch in `MenuBarGlyph.init`, and this list should grow.
        let all: [TrackingStatus] = [
            .cameraBlocked, .cameraFailed, .paused, .calibrating, .oneDisplay, .needsCalibration,
            .suspended(.screenLocked), .starting, .cameraBusy("x"), .needsAccessibility, .focusLock, .tracking,
            .noFace,
        ]
        #expect(Set(all.map { MenuBarGlyph($0) }) == Set(MenuBarGlyph.allCases), "Every glyph is used")
    }

    @Test func eachGlyphHasItsStyle() {
        #expect(
            MenuBarGlyph.tracking.style
                == MenuBarGlyph.Style(opacity: 1, hollowEnd: false, lockBadge: false, alertDot: false))
        #expect(
            MenuBarGlyph.paused.style
                == MenuBarGlyph.Style(opacity: 0.5, hollowEnd: true, lockBadge: false, alertDot: false))
        #expect(
            MenuBarGlyph.focusLock.style
                == MenuBarGlyph.Style(opacity: 1, hollowEnd: false, lockBadge: true, alertDot: false))
        #expect(
            MenuBarGlyph.attention.style
                == MenuBarGlyph.Style(opacity: 1, hollowEnd: false, lockBadge: false, alertDot: true))
    }

    @Test func theModelPicksTheGlyphFromTheStatus() async {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(h.model.menuBarGlyph == .paused, "Tracking is off by default")

        await h.startTracking()
        h.feed()
        #expect(h.model.menuBarGlyph == .tracking)

        h.model.setFocusLock(true)
        #expect(h.model.menuBarGlyph == .focusLock)
        h.model.setFocusLock(false)

        h.focus.setTrusted(false)
        h.model.refreshAccessibilityTrust()
        #expect(h.model.menuBarGlyph == .attention)
    }

    // MARK: Images

    @Test func eachImageIsAnEighteenPointTemplate() {
        for glyph in MenuBarGlyph.allCases {
            let image = MenuBarIcon.image(for: glyph)
            #expect(image.size == NSSize(width: 18, height: 18), "\(glyph)")
            #expect(image.isTemplate, "\(glyph)")
        }
    }

    @Test func theSameImageComesBackEveryTimeAndEachGlyphHasItsOwn() {
        for glyph in MenuBarGlyph.allCases {
            #expect(MenuBarIcon.image(for: glyph) === MenuBarIcon.image(for: glyph), "\(glyph)")
        }
        let images = MenuBarGlyph.allCases.map { MenuBarIcon.image(for: $0) }
        for (index, image) in images.enumerated() {
            for other in images[(index + 1)...] { #expect(image !== other) }
        }
    }

    @Test func eachImageHasSharpBitmapsForOneAndTwoTimesScreens() {
        for glyph in MenuBarGlyph.allCases {
            let reps = MenuBarIcon.image(for: glyph).representations.compactMap { $0 as? NSBitmapImageRep }
            #expect(reps.map(\.pixelsWide).sorted() == [18, 36], "\(glyph)")
            for rep in reps { #expect(rep.size == NSSize(width: 18, height: 18)) }
        }
    }

    @Test func thePartsHaveTheContractSizesInPoints() {
        #expect(MenuBarIcon.side == 18)
        #expect(MenuBarIcon.eyeRadius == 0.55)
        #expect(MenuBarIcon.outlineWidth == 1.2)
    }

    // MARK: What is drawn

    /// The strongest alpha in `area` (points, y down) of the 2x bitmap.
    private func ink(_ glyph: MenuBarGlyph, in area: CGRect) -> Double {
        let reps = MenuBarIcon.image(for: glyph).representations.compactMap { $0 as? NSBitmapImageRep }
        guard let rep = reps.first(where: { $0.pixelsWide == 36 }) else { return 0 }
        var strongest = 0.0
        for x in Int(area.minX * 2)..<Int(area.maxX * 2) {
            for y in Int(area.minY * 2)..<Int(area.maxY * 2) {
                strongest = max(strongest, Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0))
            }
        }
        return strongest
    }

    private let whole = CGRect(x: 0, y: 0, width: 18, height: 18)
    private let bottomRight = CGRect(x: 12.5, y: 13.5, width: 4, height: 2.5)
    private let topRight = CGRect(x: 14.5, y: 1.5, width: 2, height: 2)
    /// Inside the body, away from the neck and the badges.
    private let body = CGRect(x: 6, y: 12.5, width: 3, height: 1.5)

    @Test func theSolidGooseIsDrawnAtFullStrengthAndTheTopRightCornerIsFree() {
        #expect(ink(.tracking, in: whole) > 0.99)
        #expect(ink(.tracking, in: body) > 0.99, "The body")
        #expect(ink(.tracking, in: topRight) == 0, "Room for the alert dot")
    }

    @Test func thePausedGooseIsDimmedNotFaint() {
        let strongest = ink(.paused, in: whole)
        #expect(strongest > 0.45 && strongest < 0.55, "Half strength: \(strongest)")
    }

    @Test func thePausedGooseIsHollow() {
        #expect(ink(.tracking, in: body) > 0.99)
        #expect(ink(.paused, in: body) == 0, "Only the outline is drawn")
    }

    @Test func theLockBadgeIsAtTheBottomRightAndTheDotAtTheTopRight() {
        #expect(ink(.focusLock, in: bottomRight) > 0.99)
        #expect(ink(.focusLock, in: topRight) == 0)
        #expect(ink(.attention, in: topRight) > 0.99)
        #expect(ink(.focusLock, in: body) > 0.99, "The goose is still there")
        #expect(ink(.attention, in: body) > 0.99)
    }
}
