import AppKit
import SwiftUI

/// Gander's brand colors plus a few semantic helpers. System fonts and controls are used everywhere else.
enum GanderPalette {
    /// Brand colors as 24-bit RGB values (`0xRRGGBB`).
    static let forestHex: UInt32 = 0x2F5D3A
    static let sageHex: UInt32 = 0x9CAF88
    static let ivoryHex: UInt32 = 0xF6F3EA
    static let charcoalHex: UInt32 = 0x2B2B2B

    /// The lighter green that keeps Gander green readable on dark appearances.
    static let greenDarkHex: UInt32 = 0x6FAF84

    static let forest = Color(hex: forestHex)
    static let sage = Color(hex: sageHex)
    static let ivory = Color(hex: ivoryHex)
    static let charcoal = Color(hex: charcoalHex)

    /// Gander green (SPEC F24): forest in light appearances and a lighter green in dark ones, so it keeps its contrast.
    /// The accent when the user keeps "Gander green", the edge glow, and the mark in the popover.
    static let green = Color(nsColor: makeGreen())

    /// The hex value of Gander green in a light or dark appearance.
    static func greenHex(isDark: Bool) -> UInt32 {
        isDark ? greenDarkHex : forestHex
    }

    /// A dynamic AppKit color that resolves to ``greenHex(isDark:)`` for the appearance it is drawn in.
    static func makeGreen() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: greenHex(isDark: isDark))
        }
    }

    /// Amber used for "marginal" and warnings.
    static let amber = Color(red: 0.78, green: 0.52, blue: 0.10)
    /// Brick red used for "no-go" and errors.
    static let brick = Color(red: 0.69, green: 0.23, blue: 0.20)

    /// Accent for text and glyphs: forest in light mode, sage in dark mode (forest is too dark on dark).
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? sage : forest
    }

    /// Soft card background that works in both appearances.
    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : ivory
    }

    /// Series colors for per-display plots (forest first, then colorblind-friendly companions).
    private static let seriesColors: [Color] = [
        forest,
        Color(red: 0.85, green: 0.47, blue: 0.13),
        Color(red: 0.24, green: 0.43, blue: 0.66),
        Color(red: 0.56, green: 0.35, blue: 0.62),
        Color(red: 0.70, green: 0.60, blue: 0.15),
        Color(red: 0.45, green: 0.45, blue: 0.45),
    ]

    /// Color for the display at `index` in layout order (wraps around).
    static func seriesColor(at index: Int) -> Color {
        seriesColors[((index % seriesColors.count) + seriesColors.count) % seriesColors.count]
    }
}

extension Color {
    /// Creates an sRGB color from a 24-bit `0xRRGGBB` value.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension NSColor {
    /// Creates an sRGB color from a 24-bit `0xRRGGBB` value.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
