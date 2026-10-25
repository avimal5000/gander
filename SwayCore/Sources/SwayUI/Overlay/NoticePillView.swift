import AppKit

/// The Focus Lock notice (SPEC F28): a rounded pill of HUD material with an SF Symbol and a line of text. AppKit, so
/// the material blurs what is behind the panel.
@MainActor
final class NoticePillView: NSVisualEffectView {
    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 9
    private static let spacing: CGFloat = 7

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        // The HUD material is dark, so its text is light in either appearance.
        appearance = NSAppearance(named: .vibrantDark)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        iconView.contentTintColor = .labelColor
        iconView.imageScaling = .scaleNone
        addSubview(iconView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Sets the symbol and the text, lays the pill out, and returns its size.
    func configure(text: String, symbol: String) -> NSSize {
        label.stringValue = text
        label.sizeToFit()
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        iconView.image = image
        let iconSize = image?.size ?? .zero

        let contentHeight = max(label.frame.height, iconSize.height)
        let spacing = iconSize.width > 0 ? Self.spacing : 0
        let size = NSSize(
            width: Self.horizontalPadding * 2 + iconSize.width + spacing + label.frame.width,
            height: contentHeight + Self.verticalPadding * 2)
        setFrameSize(size)

        iconView.frame = NSRect(
            x: Self.horizontalPadding, y: ((size.height - iconSize.height) / 2).rounded(),
            width: iconSize.width, height: iconSize.height)
        label.setFrameOrigin(
            NSPoint(
                x: Self.horizontalPadding + iconSize.width + spacing,
                y: ((size.height - label.frame.height) / 2).rounded()))
        maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            return true
        }
        return size
    }
}
