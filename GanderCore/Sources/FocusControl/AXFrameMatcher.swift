import CoreGraphics
import Foundation

/// Matches a window-list window to its Accessibility window by frame. Pure functions over plain frames.
enum AXFrameMatcher {
    /// Position and size may each differ by up to this many points.
    static let tolerance: CGFloat = 2

    /// True when origin and size of both frames differ by at most `tolerance` per component.
    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    /// The index of the candidate whose frame matches `target`; the closest one if several match, the first
    /// on a tie. `nil` entries are windows whose frame could not be read. `nil` if nothing matches.
    static func matchingIndex(for target: CGRect, among candidates: [CGRect?]) -> Int? {
        var best: (index: Int, deviation: CGFloat)?
        for (index, candidate) in candidates.enumerated() {
            guard let candidate, matches(target, candidate) else { continue }
            let deviation =
                abs(target.origin.x - candidate.origin.x) + abs(target.origin.y - candidate.origin.y)
                + abs(target.size.width - candidate.size.width) + abs(target.size.height - candidate.size.height)
            if best == nil || deviation < (best?.deviation ?? .infinity) {
                best = (index, deviation)
            }
        }
        return best?.index
    }

    /// The window to act on: the frame match, else the app's only window, else `nil`.
    static func selectedIndex(for target: CGRect, among candidates: [CGRect?]) -> Int? {
        if let index = matchingIndex(for: target, among: candidates) {
            return index
        }
        return candidates.count == 1 ? 0 : nil
    }
}
