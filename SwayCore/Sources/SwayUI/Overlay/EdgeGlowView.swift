import AppKit

/// The edge glow (SPEC F27): a 4 pt Gander-green border along the edges of the display, with a soft glow of about 10 pt
/// just inside it that fades out from 40% opacity.
///
/// Drawn with eight thin layers along the edges (four solid borders, four gradients), so the panel holds no
/// full-screen bitmap: the middle of the display has no layer at all. Static: the panel fades it, and nothing
/// redraws while it shows.
final class EdgeGlowView: NSView {
    /// Width of the solid border.
    static let borderWidth: CGFloat = 4
    /// Width of the soft glow inside the border.
    static let glowWidth: CGFloat = 10
    /// Opacity of the glow next to the border.
    static let glowOpacity = 0.4

    /// Opacity of the glow ring `index` (0 touches the border), falling off quadratically to nearly nothing.
    static func ringOpacity(at index: Int) -> Double {
        let position = (Double(index) + 0.5) / Double(glowWidth)
        return glowOpacity * (1 - position) * (1 - position)
    }

    /// The edges, in the order the layers below are kept.
    private enum Edge: CaseIterable {
        case left, right, bottom, top
    }

    private let borders = Edge.allCases.map { _ in CALayer() }
    private let glows = Edge.allCases.map { _ in CAGradientLayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (edge, glow) in zip(Edge.allCases, glows) {
            // Unit coordinates, y up: each gradient starts at its display edge and fades toward the middle.
            switch edge {
            case .left: (glow.startPoint, glow.endPoint) = (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
            case .right: (glow.startPoint, glow.endPoint) = (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
            case .bottom: (glow.startPoint, glow.endPoint) = (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
            case .top: (glow.startPoint, glow.endPoint) = (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
            }
            let rings = Int(Self.glowWidth)
            glow.locations = (0...rings).map { NSNumber(value: Double($0) / Double(rings)) }
        }
        for sublayer in glows + borders { layer?.addSublayer(sublayer) }
        applyColors()
        layOutEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layOutEdges()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Gander green, resolved for this view's appearance (light or dark), on every layer.
    private func applyColors() {
        var green = CGColor(gray: 0, alpha: 0)
        effectiveAppearance.performAsCurrentDrawingAppearance { green = SwayPalette.makeGreen().cgColor }
        let rings = Int(Self.glowWidth)
        // One stop per point of glow, at each ring's opacity, then clear at the inner edge.
        let stops = (0...rings).map { index in
            green.copy(alpha: index < rings ? CGFloat(Self.ringOpacity(at: index)) : 0) ?? green
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for border in borders { border.backgroundColor = green }
        for glow in glows { glow.colors = stops }
        CATransaction.commit()
    }

    /// Puts each border on its edge and each glow just inside it. Side strips run the full height; the top and bottom
    /// ones run between the side borders.
    private func layOutEdges() {
        let size = bounds.size
        let border = Self.borderWidth
        let glow = Self.glowWidth
        let innerWidth = max(size.width - 2 * border, 0)
        let innerHeight = max(size.height - 2 * border, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, edge) in Edge.allCases.enumerated() {
            switch edge {
            case .left:
                borders[index].frame = CGRect(x: 0, y: 0, width: border, height: size.height)
                glows[index].frame = CGRect(x: border, y: border, width: glow, height: innerHeight)
            case .right:
                borders[index].frame = CGRect(x: size.width - border, y: 0, width: border, height: size.height)
                glows[index].frame = CGRect(x: size.width - border - glow, y: border, width: glow, height: innerHeight)
            case .bottom:
                borders[index].frame = CGRect(x: border, y: 0, width: innerWidth, height: border)
                glows[index].frame = CGRect(x: border, y: border, width: innerWidth, height: glow)
            case .top:
                borders[index].frame = CGRect(x: border, y: size.height - border, width: innerWidth, height: border)
                glows[index].frame = CGRect(x: border, y: size.height - border - glow, width: innerWidth, height: glow)
            }
        }
        CATransaction.commit()
    }
}
