import Foundation
import SwayModels

// The look of Sway (SPEC F24, F27, F28, CONTRACT 6.5.4): the accent, and the two small pieces of feedback on the
// displays, the edge glow after a switch and the notice when the shortcut toggles Focus Lock. The panels themselves
// are `FeedbackOverlayController`'s; this extension decides when they show and on which display.
extension AppModel {
    // MARK: Settings > Appearance

    /// The accent color picker. Saved at once; the windows follow because their root views read ``accentChoice``.
    func setAccentChoice(_ choice: AccentChoice) {
        guard choice != accentChoice else { return }
        defaults.set(choice.rawValue, forKey: DefaultsKey.accentChoice)
        accentChoice = choice
    }

    /// "Glow on the display that gets focus".
    func setEdgeGlowEnabled(_ enabled: Bool) {
        guard enabled != edgeGlowEnabled else { return }
        defaults.set(enabled, forKey: DefaultsKey.edgeGlowEnabled)
        edgeGlowEnabled = enabled
    }

    /// "Show a notice when the shortcut toggles Focus Lock".
    func setFocusLockNoticeEnabled(_ enabled: Bool) {
        guard enabled != focusLockNoticeEnabled else { return }
        defaults.set(enabled, forKey: DefaultsKey.focusLockNoticeEnabled)
        focusLockNoticeEnabled = enabled
    }

    /// A saved on/off setting; on when absent.
    static func storedFlag(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    // MARK: Feedback on the displays

    /// The edge glow on display `id`, after a tracking switch that moved focus there. Does nothing when the glow is off
    /// or the display is gone.
    func showEdgeGlow(on id: DisplayID) {
        guard edgeGlowEnabled, let display = layout.display(withID: id) else { return }
        environment.feedback.showGlow(on: display, animated: !environment.reduceMotion())
    }

    /// The notice for the Focus Lock state as it is now, on the display holding focus, or else the display with the
    /// menu bar. Does nothing when the notice is off or there is no display.
    func showFocusLockNotice() {
        guard focusLockNoticeEnabled, let display = noticeDisplay else { return }
        let notice = FocusLockNotice(isOn: focusLocked)
        environment.feedback.showNotice(
            notice.text, symbol: notice.symbol, on: display, animated: !environment.reduceMotion())
    }

    /// Where the Focus Lock notice shows: the display the tracking loop believes has focus, else the main display.
    var noticeDisplay: DisplayInfo? {
        loop.focusedDisplay.flatMap { layout.display(withID: $0) }
            ?? layout.displays.first { $0.isMain }
            ?? layout.displays.first
    }
}

/// The words and symbol of the Focus Lock notice (SPEC F28).
struct FocusLockNotice: Equatable {
    let isOn: Bool

    /// "Focus Lock on" or "Focus Lock off".
    var text: String { isOn ? "Focus Lock on" : "Focus Lock off" }

    /// The lock closed while it is on, open when it is off.
    var symbol: String { isOn ? "lock.fill" : "lock.open" }
}
