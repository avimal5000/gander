import CoreGraphics

/// The Swing mark (SPEC D36): an arc swinging from a small point on the left to a larger point on the right.
///
/// One definition in a 100 x 100 unit square with y pointing down, shared by the SwiftUI ``SwayMark`` and the menu bar
/// icon drawing. The arc is the quadratic curve `M 24 40 Q 50 86 76 40`; the start point is at (24, 40) and the end
/// point at (76, 40). Sizes are in the same units, so the mark looks the same at every scale.
enum SwayMarkGeometry {
    /// Side of the unit square.
    static let unitSize: CGFloat = 100
    static let start = CGPoint(x: 24, y: 40)
    static let end = CGPoint(x: 76, y: 40)
    /// The quadratic curve's control point.
    static let control = CGPoint(x: 50, y: 86)

    /// Stroke width of the arc.
    static let arcWidth: CGFloat = 7
    /// Radius of the small point at the start of the swing.
    static let startRadius: CGFloat = 5.5
    /// Radius of the larger point at the end of the swing.
    static let endRadius: CGFloat = 8
    /// Stroke width of the ring that replaces the end point in the hollow (paused) state.
    static let ringWidth: CGFloat = 4

    /// The point of the arc at `t` (0 at the start point, 1 at the end point).
    static func arcPoint(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// The two control points of the cubic curve that equals the arc, for APIs without quadratic curves.
    static var cubicControls: (first: CGPoint, second: CGPoint) {
        (
            CGPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y)),
            CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y))
        )
    }

    /// What the mark covers, points and stroke included, in unit coordinates.
    static var visualBounds: CGRect {
        let bottom = arcPoint(at: 0.5).y + arcWidth / 2
        let left = start.x - startRadius
        let right = end.x + endRadius
        let top = min(start.y - startRadius, end.y - endRadius)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Where unit coordinates land in a drawing area: a uniform scale and an offset.
    struct Placement: Equatable {
        let scale: CGFloat
        let offset: CGPoint

        /// A point in unit coordinates, in the drawing area.
        func point(_ unit: CGPoint) -> CGPoint {
            CGPoint(x: offset.x + unit.x * scale, y: offset.y + unit.y * scale)
        }

        /// A length in unit coordinates, in the drawing area.
        func length(_ unit: CGFloat) -> CGFloat {
            unit * scale
        }
    }

    /// Scales and centers ``visualBounds`` so the mark fills `rect` as much as it can: for small marks (the menu bar,
    /// the popover header), where the unit square's padding would leave the mark tiny.
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

    /// Maps the whole unit square onto the largest centered square in `rect`: the mark with the same padding it has in
    /// the app icon.
    static func placement(unitSquareIn rect: CGRect) -> Placement {
        let side = min(rect.width, rect.height)
        return Placement(
            scale: side / unitSize,
            offset: CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        )
    }
}
