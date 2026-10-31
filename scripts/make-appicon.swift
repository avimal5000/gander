// Renders Gander's app icon (the goose mark; GanderMarkGeometry holds the same outline) into the asset catalog at every macOS size.
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

    // The goose, in its own coordinates (y down), fitted into the tile: 68% of the tile's height, centred.
    let bounds = CGRect(x: 14, y: 10.9, width: 68.3, height: 75.8)
    let scale = tile.height * 0.68 / bounds.height
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: tile.midX + (x - bounds.midX) * scale, y: tile.midY - (y - bounds.midY) * scale)
    }
    let body = CGMutablePath()
    body.move(to: p(14, 70))
    body.addCurve(to: p(42, 64), control1: p(22, 72), control2: p(32, 66))
    body.addCurve(to: p(49, 50), control1: p(48, 63), control2: p(50, 58))
    body.addCurve(to: p(47, 26), control1: p(48, 40), control2: p(46, 34))
    body.addCurve(to: p(57, 11), control1: p(47.5, 18), control2: p(50, 12))
    body.addCurve(to: p(66, 15.5), control1: p(62, 10.5), control2: p(65, 13))
    body.addLine(to: p(76.5, 18))
    body.addLine(to: p(67, 22.5))
    body.addCurve(to: p(60.5, 28), control1: p(64, 23.5), control2: p(61.5, 24.5))
    body.addCurve(to: p(62, 46), control1: p(59.5, 34), control2: p(60.5, 40))
    body.addCurve(to: p(78, 60), control1: p(64, 52), control2: p(72, 54))
    body.addCurve(to: p(70, 84), control1: p(86, 68), control2: p(82, 80))
    body.addCurve(to: p(14, 70), control1: p(54, 90), control2: p(28, 86))
    body.closeSubpath()
    let eyeRadius = max(1.6, px <= 32 ? 2.6 : 1.6) * scale
    let eyeCenter = p(60.8, 17.1)
    body.addEllipse(in: CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
    ctx.addPath(body)
    ctx.setFillColor(ivory)
    ctx.fillPath(using: .evenOdd)

    // The wing, in sage; at the smallest sizes it would only be noise.
    if px > 32 {
        let wing = CGMutablePath()
        wing.move(to: p(32, 73))
        wing.addCurve(to: p(69, 71), control1: p(42, 65), control2: p(58, 65))
        wing.addCurve(to: p(32, 73), control1: p(60, 80), control2: p(42, 80))
        wing.closeSubpath()
        ctx.addPath(wing)
        ctx.setFillColor(sage)
        ctx.fillPath()
    }

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
