import CoreGraphics
import Foundation
import GanderModels

/// Decides whether the window the user is working in already shows on a display, so a switch there must leave every
/// window where it is (SPEC D52).
///
/// Without this check, a switch to the display the user is already on raised that display's last-used window. That
/// is a different window whenever the focused one is assigned to another display (it straddles two displays, so most
/// of it is on the other one) or the focused-display poll is up to a second stale, and it brought a window from far
/// back in the stack over the one in use.
enum AlreadyFocusedCheck {
    /// The focused window also counts as showing on a display it covers at least this share of, even when most of
    /// the window is on another display.
    static let minimumDisplayShare: CGFloat = 0.25

    /// The window-list record of `processID`'s focused window when it shows on `display`, else `nil`.
    ///
    /// - Parameters:
    ///   - focusedFrame: The Accessibility frame of the app's focused window, `nil` when it has none or it could not
    ///     be read. When it is `nil` or matches no normal window, the app's frontmost normal window stands in for
    ///     it, but only while it is the topmost normal window of its display.
    ///   - records: The window list, front to back.
    static func focusedRecord(
        on display: DisplayID,
        processID: Int32,
        focusedFrame: CGRect?,
        in records: [WindowRecord],
        displays: [QuartzDisplayFrame],
        ownProcessID: Int32
    ) -> WindowRecord? {
        guard processID != ownProcessID, let target = displays.first(where: { $0.id == display }) else { return nil }
        let candidates = records.filter {
            $0.processID == processID && NormalWindowFilter.isNormal($0, ownProcessID: ownProcessID)
        }
        let matched = focusedFrame.flatMap { frame in
            candidates.first { AXFrameMatcher.matches($0.bounds, frame) }
        }
        if let matched { return shows(matched.bounds, on: target, among: displays) ? matched : nil }
        // A focused panel matches no normal window: its app's frontmost normal window is the one in use. Unless another
        // app's window covers it: Finder with the desktop clicked has no focused window, and its frontmost window can
        // be far back, so counting that one would leave a look at the display doing nothing.
        guard let standIn = candidates.first, shows(standIn.bounds, on: target, among: displays) else { return nil }
        let topmost = LastUsedWindowSelector.select(from: records, displays: displays, ownProcessID: ownProcessID)
        return topmost.values.contains { $0.number == standIn.number } ? standIn : nil
    }

    /// True when `bounds` is assigned to `target`, or covers at least ``minimumDisplayShare`` of it.
    static func shows(_ bounds: CGRect, on target: QuartzDisplayFrame, among displays: [QuartzDisplayFrame]) -> Bool {
        if DisplayGeometry.assignedDisplay(for: bounds, in: displays) == target.id { return true }
        let displayArea = target.frame.width * target.frame.height
        let overlap = target.frame.intersection(bounds)
        guard displayArea > 0, !overlap.isNull else { return false }
        return overlap.width * overlap.height >= minimumDisplayShare * displayArea
    }
}
