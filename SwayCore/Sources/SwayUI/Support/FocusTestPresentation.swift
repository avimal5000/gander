import Foundation
import SwayModels

/// Wording and row layout for the Focus Test window. Pure functions of model values.
enum FocusTestPresentation {
    /// One display's row.
    struct Row: Identifiable, Equatable {
        let id: DisplayID
        /// The display's label, with "(focused)" when it holds the focused window.
        let title: String
        let isFocused: Bool
        /// The last-used window: "App — Title", "App", or "No window".
        let windowText: String
        let hasWindow: Bool
    }

    static let accessibilityGranted = "Accessibility: Granted"
    static let accessibilityNotGranted = "Accessibility: Not granted"
    static let accessibilityExplanation =
        "Sway needs Accessibility access to move keyboard focus to a window on the display you look at. "
        + "It never moves the cursor and never reads window contents."

    /// One row per display in layout order.
    static func rows(layout: DisplayLayout, windows: [DisplayID: WindowSummary], focused: DisplayID?) -> [Row] {
        let labels = DisplayLabeler.labels(for: layout)
        return layout.displays.map { display in
            let label = labels[display.id] ?? display.name
            let isFocused = display.id == focused
            return Row(
                id: display.id,
                title: isFocused ? "\(label) (focused)" : label,
                isFocused: isFocused,
                windowText: windowText(windows[display.id]),
                hasWindow: windows[display.id] != nil
            )
        }
    }

    /// "App — Title" when Accessibility gave a title, "App" without one, "No window" when the display has none.
    static func windowText(_ window: WindowSummary?) -> String {
        guard let window else { return "No window" }
        guard let title = window.title, !title.isEmpty else { return window.appName }
        return "\(window.appName) \u{2014} \(title)"
    }

    /// The log line for a focus result. Names the app and display, never a window title.
    static func logText(for result: FocusResult, displayName: (DisplayID) -> String) -> String {
        switch result {
        case .focused(let window, let method, let milliseconds):
            "Focused \(window.appName) via \(methodText(method)) in \(milliseconds) ms"
        case .noWindow(let display):
            "No window on \(displayName(display))"
        case .notTrusted:
            "Accessibility permission needed"
        case .failed(_, let reason):
            "Failed: \(reason)"
        }
    }

    private static func methodText(_ method: FocusMethod) -> String {
        switch method {
        case .appActivation: "app activation"
        case .accessibilityFrontmost: "Accessibility frontmost"
        }
    }
}
