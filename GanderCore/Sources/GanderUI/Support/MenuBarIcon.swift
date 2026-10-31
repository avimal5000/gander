import AppKit

/// The menu bar icon images (SPEC F25, D37): the goose mark as an 18 x 18 pt template image, one per ``MenuBarGlyph``.
///
/// Each image is drawn once, into bitmaps at 1x and 2x, the first time its glyph is asked for, and kept for the life
/// of the app. The images are templates, so the menu bar tints them for light and dark; only the alpha channel
/// matters, and the badges are cut out of the mark with a clear ring so they read at this size.
@MainActor
enum MenuBarIcon {
    /// Side of the image in points.
    static let side: CGFloat = 18
    /// Pixel scales of the bitmaps in each image.
    private static let scales = [1, 2]
    /// Sizes of the mark's parts at this size, in points (CONTRACT 6.5.4). The shape comes from ``GanderMarkGeometry``;
    /// the eye is set by hand, because a hole that small must be larger than the mark scaled down.
    static let eyeRadius: CGFloat = 0.55
    /// Width of the outline that is the hollow (paused) goose.
    static let outlineWidth: CGFloat = 1.2

    /// The area the mark is fitted into, in points, y down. It is a little left of and above the center of the image,
    /// which leaves a corner free on the right for the badges.
    private static let markArea = CGRect(x: 0.75, y: 0.8, width: 15, height: 15)

    /// The image for `glyph`: always the same instance.
    static func image(for glyph: MenuBarGlyph) -> NSImage {
        switch glyph {
        case .tracking: tracking
        case .paused: paused
        case .focusLock: focusLock
        case .attention: attention
        }
    }

    private static let tracking = makeImage(for: .tracking)
    private static let paused = makeImage(for: .paused)
    private static let focusLock = makeImage(for: .focusLock)
    private static let attention = makeImage(for: .attention)

    private static func makeImage(for glyph: MenuBarGlyph) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in scales {
            if let rep = render(glyph.style, scale: scale) { image.addRepresentation(rep) }
        }
        image.isTemplate = true
        return image
    }

    /// Draws the glyph into a bitmap of `scale` pixels per point, or `nil` when no bitmap context can be made.
    private static func render(_ style: MenuBarGlyph.Style, scale: Int) -> NSBitmapImageRep? {
        let pixels = Int(side) * scale
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        // The size comes first: the context takes its scale from it.
        rep.size = NSSize(width: side, height: side)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        // Unit coordinates run y down, so flip the context once and draw everything in that orientation.
        context.cgContext.translateBy(x: 0, y: side)
        context.cgContext.scaleBy(x: 1, y: -1)
        draw(style, in: context)
        return rep
    }

    private static func draw(_ style: MenuBarGlyph.Style, in context: NSGraphicsContext) {
        let placement = GanderMarkGeometry.placement(fitting: markArea)

        // The mark is drawn as one group, so a dimmed glyph has one even opacity where the shapes overlap.
        let cg = context.cgContext
        cg.setAlpha(CGFloat(style.opacity))
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        NSColor.black.set()
        drawMark(style, placement: placement)
        cg.endTransparencyLayer()
        cg.setAlpha(1)

        if style.lockBadge { drawLockBadge(in: context) }
        if style.alertDot { drawAlertDot(in: context) }
    }

    private static func drawMark(_ style: MenuBarGlyph.Style, placement: GanderMarkGeometry.Placement) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let silhouette = GanderMarkGeometry.silhouette(in: placement)
        let eye = GanderMarkGeometry.eye(in: placement, radius: eyeRadius)
        if style.hollowEnd {
            // The paused goose is an outline with its eye kept as a dot.
            cg.addPath(silhouette)
            cg.setLineWidth(outlineWidth)
            cg.setLineJoin(.round)
            cg.strokePath()
            cg.addPath(eye)
            cg.fillPath()
        } else {
            cg.addPath(silhouette)
            cg.addPath(eye)
            cg.fillPath(using: .evenOdd)
        }
    }

    // MARK: Badges

    /// Where the lock badge sits: bottom right. Points, y down.
    private static let lockBody = CGRect(x: 12.4, y: 12, width: 5.2, height: 4.4)
    private static let alertCenter = CGPoint(x: 15.5, y: 2.5)
    private static let alertRadius: CGFloat = 2.0
    /// Width of the clear ring around a badge.
    private static let badgeGap: CGFloat = 1

    private static func drawLockBadge(in context: NSGraphicsContext) {
        let shackle = CGRect(x: lockBody.minX + 1.1, y: lockBody.minY - 2.4, width: lockBody.width - 2.2, height: 5.2)
        let outline = lockBody.union(shackle).insetBy(dx: -badgeGap, dy: -badgeGap)
        cutOut(NSBezierPath(roundedRect: outline, xRadius: 2.2, yRadius: 2.2), in: context)

        NSColor.black.set()
        let arch = NSBezierPath(roundedRect: shackle, xRadius: shackle.width / 2, yRadius: shackle.width / 2)
        arch.lineWidth = 1.2
        arch.stroke()
        NSBezierPath(roundedRect: lockBody, xRadius: 1.2, yRadius: 1.2).fill()
    }

    private static func drawAlertDot(in context: NSGraphicsContext) {
        cutOut(disc(at: alertCenter, radius: alertRadius + 0.9), in: context)
        NSColor.black.set()
        disc(at: alertCenter, radius: alertRadius).fill()
    }

    /// Clears everything under `path`, so a badge has a gap around it.
    private static func cutOut(_ path: NSBezierPath, in context: NSGraphicsContext) {
        let saved = context.compositingOperation
        context.compositingOperation = .clear
        path.fill()
        context.compositingOperation = saved
    }

    private static func disc(at center: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(
            ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
