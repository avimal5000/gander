import CoreGraphics
import Testing

@testable import SwayUI

@Suite("Swing mark geometry")
struct SwayMarkGeometryTests {
    private typealias Geometry = SwayMarkGeometry

    private func close(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    // MARK: The definition

    @Test func theMarkIsTheArcFromTheContract() {
        #expect(Geometry.unitSize == 100)
        #expect(Geometry.start == CGPoint(x: 24, y: 40))
        #expect(Geometry.end == CGPoint(x: 76, y: 40))
        #expect(Geometry.control == CGPoint(x: 50, y: 86))
    }

    @Test func theArcRunsFromTheStartToTheEndAndDipsBetween() {
        #expect(Geometry.arcPoint(at: 0) == Geometry.start)
        #expect(Geometry.arcPoint(at: 1) == Geometry.end)
        // Quadratic midpoint: a quarter of each end plus half of the control point; y points down.
        #expect(Geometry.arcPoint(at: 0.5) == CGPoint(x: 50, y: 63))
        for t in stride(from: 0.1, through: 0.9, by: 0.1) {
            #expect(Geometry.arcPoint(at: t).y > Geometry.start.y, "The arc swings below the two points")
        }
    }

    @Test func theCubicControlsDrawTheSameCurveAsTheQuadratic() {
        let controls = Geometry.cubicControls
        for t in stride(from: 0.0, through: 1.0, by: 0.125) {
            let u = 1 - t
            let cubic = CGPoint(
                x: u * u * u * Geometry.start.x + 3 * u * u * t * controls.first.x + 3 * u * t * t * controls.second.x
                    + t * t * t * Geometry.end.x,
                y: u * u * u * Geometry.start.y + 3 * u * u * t * controls.first.y + 3 * u * t * t * controls.second.y
                    + t * t * t * Geometry.end.y)
            #expect(close(cubic, Geometry.arcPoint(at: t)), "t = \(t)")
        }
    }

    @Test func theEndPointIsLargerThanTheStartPoint() {
        #expect(Geometry.endRadius > Geometry.startRadius)
        #expect(Geometry.arcWidth > 0)
        #expect(Geometry.ringWidth < Geometry.endRadius)
    }

    @Test func theVisualBoundsHoldTheWholeMark() {
        let bounds = Geometry.visualBounds
        #expect(bounds.minX == Geometry.start.x - Geometry.startRadius)
        #expect(bounds.maxX == Geometry.end.x + Geometry.endRadius)
        #expect(bounds.minY == Geometry.end.y - Geometry.endRadius)
        #expect(bounds.maxY == 63 + Geometry.arcWidth / 2, "The lowest point of the arc, with its stroke")
        #expect(CGRect(x: 0, y: 0, width: 100, height: 100).contains(bounds), "Inside the unit square")
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
        #expect(abs(mapped.width - area.width) < 1e-9, "The wide mark fills the width")
        #expect(abs(mapped.midX - area.midX) < 1e-9)
        #expect(abs(mapped.midY - area.midY) < 1e-9)
        #expect(placement.scale == area.width / bounds.width)
    }

    @Test func fittingATallAreaIsLimitedByItsWidth() {
        let tall = Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 30, height: 90))
        let square = Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 30, height: 30))
        #expect(tall.scale == square.scale)
        #expect(Geometry.placement(fitting: CGRect(x: 0, y: 0, width: 90, height: 5)).scale < square.scale)
    }

    @Test func theUnitSquareKeepsTheAppIconPadding() {
        let placement = Geometry.placement(unitSquareIn: CGRect(x: 0, y: 0, width: 64, height: 64))
        #expect(placement.scale == 0.64)
        #expect(placement.point(Geometry.start) == CGPoint(x: 24 * 0.64, y: 40 * 0.64))
        #expect(placement.point(CGPoint(x: 50, y: 50)) == CGPoint(x: 32, y: 32), "The middle of the square")

        let wide = Geometry.placement(unitSquareIn: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(wide.scale == 1)
        #expect(wide.point(CGPoint(x: 50, y: 50)) == CGPoint(x: 100, y: 50), "A square centered in a wide area")
    }

    @Test func lengthsScaleWithThePlacement() {
        let placement = Geometry.placement(unitSquareIn: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(placement.length(Geometry.arcWidth) == 14)
    }
}
