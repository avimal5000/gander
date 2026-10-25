// Renders Sway's app icon (SPEC D36, option A "Swing") into the asset catalog at every macOS size.
// Usage: swift scripts/make-appicon.swift <output .appiconset folder> [preview.png]
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let forest = CGColor(srgbRed: 0x2F / 255, green: 0x5D / 255, blue: 0x3A / 255, alpha: 1)
let forestTop = CGColor(srgbRed: 0x37 / 255, green: 0x6B / 255, blue: 0x44 / 255, alpha: 1)
let sage = CGColor(srgbRed: 0x9C / 255, green: 0xAF / 255, blue: 0x88 / 255, alpha: 1)
let ivory = CGColor(srgbRed: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEA / 255, alpha: 1)

/// Draws the icon on a `px` × `px` canvas. Apple's grid: an 824-unit rounded square centred in 1024.
func render(px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow, as macOS icons carry, only where it can show.
    if px >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
        ctx.addPath(shape)
        ctx.setFillColor(forest)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // The tile: forest green, a touch lighter at the top.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [forestTop, forest] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    ctx.restoreGState()

    // The mark, in a 100-unit square with y down (SwayMarkGeometry), mapped onto the tile.
    let unit = tile.width / 100
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * unit, y: tile.maxY - y * unit) }
    // Thicker strokes at the smallest sizes so the arc survives.
    let (stroke, small, big): (CGFloat, CGFloat, CGFloat) =
        px <= 16 ? (10, 7, 10.5) : px <= 32 ? (8.5, 6.2, 9.4) : (7, 5.5, 8.5)

    let arc = CGMutablePath()
    arc.move(to: point(24, 40))
    arc.addQuadCurve(to: point(76, 40), control: point(50, 86))
    ctx.addPath(arc)
    ctx.setStrokeColor(ivory)
    ctx.setLineWidth(stroke * unit)
    ctx.setLineCap(.round)
    ctx.strokePath()

    func dot(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        let r = radius * unit
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }
    dot(point(24, 40), small, sage)
    dot(point(76, 40), big, ivory)

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        write(render(px: points * scale), to: folder.appendingPathComponent(name))
        print("wrote \(name) (\(points * scale) px)")
    }
}
// A large preview for review.
if CommandLine.arguments.count > 2 {
    write(render(px: 1024), to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
