// Renders the background of the DMG window: a heading, a dashed arrow from Gander to the Applications folder, and the
// first-open hint. scripts/dmg-settings.py places the icons on top, so the coordinates here and there
// must match. Writes a 1x and a 2x PNG; scripts/release.sh combines them into one TIFF. --notarized leaves out the
// first-open hint, since a notarized Gander opens without a warning.
// Usage: swift scripts/make-dmg-background.swift <output folder> [--notarized]
import AppKit

let width: CGFloat = 660
let height: CGFloat = 420
/// Icon centres, in points from the window's top-left corner. Must match `icon_locations` in dmg-settings.py.
let appCentre = CGPoint(x: 170, y: 200)
let applicationsCentre = CGPoint(x: 490, y: 200)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let forestDeep = color(0x17_2E_1F)
let forest = color(0x2F_5D_3A)
let moss = color(0x5E_7D_55)
let ivory = color(0xF6_F3_EA)

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawCentred(_ text: String, y: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.boundingRect(with: CGSize(width: width - 80, height: 200), options: [.usesLineFragmentOrigin])
    string.draw(
        with: CGRect(x: 40, y: y, width: width - 80, height: ceil(size.height)), options: [.usesLineFragmentOrigin])
}

func drawBackground(notarized: Bool) {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)

    // Deep forest, a little lighter towards the middle.
    NSGradient(colors: [forestDeep, forest, forestDeep], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(in: bounds, angle: 90)

    // A soft moss glow behind the icons. Finder draws the icon names in black over a background picture, even in dark
    // mode, so the glow keeps them readable.
    let glow = NSGradient(colors: [moss, moss.withAlphaComponent(0)])!
    for centre in [appCentre, applicationsCentre] {
        glow.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: 150, options: [])
    }

    drawCentred("Drag the goose home", y: 44, font: roundedFont(30, .bold), color: ivory)
    drawCentred(
        "Drop Gander on the Applications folder to install it.", y: 90, font: roundedFont(14, .medium),
        color: ivory.withAlphaComponent(0.78))

    // A dashed arc from Gander over to Applications, ending in an arrowhead.
    let start = CGPoint(x: appCentre.x + 82, y: appCentre.y - 4)
    let end = CGPoint(x: applicationsCentre.x - 86, y: applicationsCentre.y - 4)
    let control = CGPoint(x: (start.x + end.x) / 2, y: appCentre.y - 46)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: control, controlPoint2: control)
    arc.lineWidth = 3.5
    arc.lineCapStyle = .round
    arc.setLineDash([0.1, 10], count: 2, phase: 0)
    ivory.withAlphaComponent(0.85).setStroke()
    arc.stroke()

    // The arrowhead follows the curve's direction where it lands.
    let angle = atan2(end.y - control.y, end.x - control.x)
    func offset(_ by: CGFloat, _ length: CGFloat) -> CGPoint {
        CGPoint(x: end.x + cos(angle + by) * length, y: end.y + sin(angle + by) * length)
    }
    let head = NSBezierPath()
    head.move(to: offset(.pi - 0.5, 13))
    head.line(to: end)
    head.line(to: offset(.pi + 0.5, 13))
    head.lineWidth = 3.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    guard !notarized else { return }
    drawCentred(
        "First open: if macOS says it can’t verify Gander, go to System Settings → Privacy & Security\nand click Open Anyway.",
        y: 360, font: roundedFont(11, .regular), color: ivory.withAlphaComponent(0.62))
}

func render(scale: CGFloat, notarized: Bool, to url: URL) throws {
    let pixelsHigh = Int(height * scale)
    let cg = CGContext(
        data: nil, width: Int(width * scale), height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flipped, so y runs down from the top like Finder's icon positions.
    cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    drawBackground(notarized: notarized)
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
    rep.size = CGSize(width: width, height: height)  // 144 dpi for the 2x file, so the TIFF pairs them up
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let notarized = arguments.contains("--notarized")
let paths = arguments.filter { $0 != "--notarized" }
guard paths.count == 1 else {
    FileHandle.standardError.write(
        "Usage: swift scripts/make-dmg-background.swift <output folder> [--notarized]\n".data(using: .utf8)!)
    exit(2)
}
let folder = URL(fileURLWithPath: paths[0], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try render(scale: 1, notarized: notarized, to: folder.appendingPathComponent("background.png"))
try render(scale: 2, notarized: notarized, to: folder.appendingPathComponent("background@2x.png"))
print("Wrote \(folder.path)/background.png and background@2x.png")
