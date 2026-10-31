import Foundation
import SwiftUI

/// The accent the user chose in Settings > Appearance (SPEC F24, D35).
///
/// The choice is applied with SwiftUI's `.tint`, because an accent color in the asset catalog yields to a system
/// accent the user picked. Saved under `gander.accentChoice`; an absent or unreadable value means Gander green.
enum AccentChoice: String, CaseIterable, Equatable, Sendable, Identifiable {
    /// Gander green (the default).
    case gander
    /// Follow the system accent color.
    case system

    var id: String { rawValue }

    /// The tint to apply: Gander green, or `nil` to leave SwiftUI's own accent in place.
    var tint: Color? {
        switch self {
        case .gander: GanderPalette.green
        case .system: nil
        }
    }

    /// The label of this choice in Settings.
    var title: String {
        switch self {
        case .gander: "Gander green"
        case .system: "Match macOS"
        }
    }

    /// The saved choice, or Gander green when absent or unreadable.
    static func stored(in defaults: UserDefaults) -> AccentChoice {
        defaults.string(forKey: DefaultsKey.accentChoice).flatMap(AccentChoice.init(rawValue:)) ?? .gander
    }
}
