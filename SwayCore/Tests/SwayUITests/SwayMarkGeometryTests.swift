import CoreGraphics
import Testing

@testable import SwayUI

@Suite("Goose mark geometry")
struct SwayMarkGeometryTests {
    private typealias Geometry = SwayMarkGeometry

    // MARK: The definition

    @Test func theSilhouetteFitsItsVisualBoundsInsideTheUnitSquare() {
        let identity = Geometry.Placement(scale: 1, offset: .zero)
        let box = Geometry.silhouette(in: identity).boundingBoxOfPath
        let bounds = Geometry.visualBounds
        #expect(bounds.insetBy(dx: -1, dy: -1).contains(box), "The bounds hold the goose: \(box)")
        #expect(box.width > bounds.width - 1 && box.height > bounds.height - 1, "...and are not loose: \(box)")
        #expect(CGRect(x: 0, y: 0, width: 100, height: 100).contains(bounds))
    }

    @Test func theEyeAndTheWingSitInsideTheGoose() {
        let identity = Geometry.Placement(scale: 1, offset: .zero)
        let silhouette = Geometry.silhouette(in: identity)
        #expect(silhouette.contains(Geometry.eyeCenter), "The eye is in the head")
        #expect(silhouette.contains(CGPoint(x: 50, y: 72)), "The wing lies on the body")
        let wing = Geometry.wing(in: identity).boundingBoxOfPath
        #expect(silhouette.boundingBoxOfPath.contains(wing))
    }

    // MARK: Placement

    @Test func fittingScalesUniformlyAndCentersTheBounds() {
        let area = CGRect(x: 10, y: 20, width: 40, height: 40)
        let placement = Geometry.placement(fitting: area)

        let bounds = Geometry.visualBounds
        let mapped = CGRect(
            origin: placement.point(bounds.origin),
            size: CGSize(width: placement.length(bounds.width), height: placement.length(bounds.height)))
        #expect(area.contains(mapped.insetBy(dx: 1e-6, dy: 1e-6)), "Inside the area")
        #expect(abs(mapped.height - area.height) < 1e-9, "The goose is taller than wide, so it fills the height")
        #expect(abs(mapped.midX - area.midX) < 1e-9)
        #expect(abs(mapped.midY - area.midY) < 1e-9)
        #expect(placement.scale == area.height / bounds.height)
    }

    @Test func fittingIsLimitedByTheTighterSide() {
        let bounds = Geometry.visualBounds
        let tall = Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 30, height: 90))
        #expect(tall.scale == 30 / bounds.width, "A tall, narrow area is limited by its width")
        let square = Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 30, height: 30))
        #expect(square.scale == 30 / bounds.height, "The goose is taller than wide")
        #expect(Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 90, height: 5)).scale < square.scale)
    }

    @Test func theUnitSquareKeepsTheAppIconPadding() {
        let area = CGRect(x: 0, y: 0, width: 100, height: 100)
        let placement = Geometry.placement(unitSquareIn: area)
        let bounds = Geometry.visualBounds
        let mapped = CGRect(
            origin: placement.point(bounds.origin),
            size: CGSize(width: placement.length(bounds.width), height: placement.length(bounds.height)))
        #expect(abs(mapped.midX - 50) < 1e-9 && abs(mapped.midY - 50) < 1e-9, "Centered")
        #expect(abs(mapped.maxY - 84) < 1e-9, "Padding of \(Geometry.squarePadding) at the bottom")

        let wide = Geometry.placement(unitSquareIn: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(wide.scale == placement.scale, "A square centered in a wide area")
    }

    @Test func lengthsScaleWithThePlacement() {
        let placement = Geometry.Placement(scale: 2, offset: .zero)
        #expect(placement.length(Geometry.eyeRadius) == 3.2)
    }
}
