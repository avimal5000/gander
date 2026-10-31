import CoreGraphics
import Foundation

/// How long a piece of feedback takes (CONTRACT 6.5.4). Pure, so the numbers are unit tested.
struct FeedbackTiming: Equatable {
    /// Seconds to fade in.
    var fadeIn: TimeInterval
    /// Seconds fully visible between the fades.
    var hold: TimeInterval
    /// Seconds to fade out.
    var fadeOut: TimeInterval
    /// Seconds fully visible, then gone, when motion is reduced and nothing fades.
    var plainDuration: TimeInterval

    /// The edge glow: fade in 0.1 s, hold 0.05 s, fade out 0.2 s; 0.35 s without fading.
    static let glow = FeedbackTiming(fadeIn: 0.1, hold: 0.05, fadeOut: 0.2, plainDuration: 0.35)
    /// The Focus Lock notice: fade in 0.15 s, hold 1 s, fade out 0.3 s; 1.3 s without fading.
    static let notice = FeedbackTiming(fadeIn: 0.15, hold: 1, fadeOut: 0.3, plainDuration: 1.3)

    /// Seconds from appearing to being gone.
    func totalDuration(animated: Bool) -> TimeInterval {
        animated ? fadeIn + hold + fadeOut : plainDuration
    }
}

/// Where the panels sit on a display.
enum FeedbackLayout {
    /// Distance from the top of the display's visible frame to the top of the notice.
    static let noticeTopOffset: CGFloat = 48

    /// The notice's frame: centered horizontally, `noticeTopOffset` below the top of `visibleFrame`. AppKit
    /// coordinates (y up), on whole points.
    static func noticeFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (visibleFrame.maxY - noticeTopOffset - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }
}
