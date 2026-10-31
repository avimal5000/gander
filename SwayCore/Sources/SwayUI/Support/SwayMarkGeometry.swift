import CoreGraphics

/// The Gander mark: a goose in profile, head up and looking right, with a wing.
///
/// One definition in goose coordinates (y pointing down), shared by the SwiftUI ``SwayMark``, the menu bar icon drawing
/// and the app icon script. The goose spans ``visualBounds``; a ``Placement`` maps it into a drawing area, so the mark
/// looks the same at every scale.
enum SwayMarkGeometry {
    /// Side of the square the mark sits in when it keeps the app icon's padding.
    static let unitSize: CGFloat = 100
    /// What the goose covers, in goose coordinates.
    static let visualBounds = CGRect(x: 14, y: 10.9, width: 68.3, height: 75.8)
    /// The eye: a small round hole in the head.
    static let eyeCenter = CGPoint(x: 60.8, y: 17.1)
    static let eyeRadius: CGFloat = 1.6
    /// Share of the unit square left empty on each side when the mark keeps the app icon's padding.
    static let squarePadding: CGFloat = 0.16

    /// Where goose coordinates land in a drawing area: a uniform scale and an offset.
    struct Placement: Equatable {
        let scale: CGFloat
        let offset: CGPoint

        /// A point in goose coordinates, in the drawing area.
        func point(_ unit: CGPoint) -> CGPoint {
            CGPoint(x: offset.x + unit.x * scale, y: offset.y + unit.y * scale)
        }

        /// A length in goose coordinates, in the drawing area.
        func length(_ unit: CGFloat) -> CGFloat {
            unit * scale
        }
    }

    /// The outline of the body, neck, head and beak, without the eye.
    static func silhouette(in placement: Placement) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { placement.point(CGPoint(x: x, y: y)) }
        let path = CGMutablePath()
        path.move(to: p(14, 70))
        path.addCurve(to: p(42, 64), control1: p(22, 72), control2: p(32, 66))
        path.addCurve(to: p(49, 50), control1: p(48, 63), control2: p(50, 58))
        path.addCurve(to: p(47, 26), control1: p(48, 40), control2: p(46, 34))
        path.addCurve(to: p(57, 11), control1: p(47.5, 18), control2: p(50, 12))
        path.addCurve(to: p(66, 15.5), control1: p(62, 10.5), control2: p(65, 13))
        path.addLine(to: p(76.5, 18))
        path.addLine(to: p(67, 22.5))
        path.addCurve(to: p(60.5, 28), control1: p(64, 23.5), control2: p(61.5, 24.5))
        path.addCurve(to: p(62, 46), control1: p(59.5, 34), control2: p(60.5, 40))
        path.addCurve(to: p(78, 60), control1: p(64, 52), control2: p(72, 54))
        path.addCurve(to: p(70, 84), control1: p(86, 68), control2: p(82, 80))
        path.addCurve(to: p(14, 70), control1: p(54, 90), control2: p(28, 86))
        path.closeSubpath()
        return path
    }

    /// The eye, as a circle to cut out of the silhouette (fill both with the even-odd rule).
    static func eye(in placement: Placement, radius: CGFloat? = nil) -> CGPath {
        let center = placement.point(eyeCenter)
        let r = radius ?? placement.length(eyeRadius)
        return CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
    }

    /// The wing: a leaf shape laid on the body.
    static func wing(in placement: Placement) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { placement.point(CGPoint(x: x, y: y)) }
        let path = CGMutablePath()
        path.move(to: p(32, 73))
        path.addCurve(to: p(69, 71), control1: p(42, 65), control2: p(58, 65))
        path.addCurve(to: p(32, 73), control1: p(60, 80), control2: p(42, 80))
        path.closeSubpath()
        return path
    }

    /// Scales and centers ``visualBounds`` so the goose fills `rect` as much as it can: for small marks (the menu bar,
    /// the popover header), where padding would leave the mark tiny.
    static func placement(fitting rect: CGRect) -> Placement {
        let bounds = visualBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        return Placement(
            scale: scale,
            offset: CGPoint(
                x: rect.midX - bounds.midX * scale,
                y: rect.midY - bounds.midY * scale
            ))
    }

    /// The goose in the largest centered square in `rect`, with the padding it has in the app icon.
    static func placement(unitSquareIn rect: CGRect) -> Placement {
        let side = min(rect.width, rect.height)
        let inner = side * (1 - 2 * squarePadding)
        let square = CGRect(x: rect.midX - inner / 2, y: rect.midY - inner / 2, width: inner, height: inner)
        return placement(fitting: square)
    }
}
