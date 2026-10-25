import CoreGraphics
import Foundation
import SwayModels

/// A display's frame in Quartz global coordinates (origin at the top-left of the main display, y down).
struct QuartzDisplayFrame: Equatable, Sendable {
    let id: DisplayID
    let frame: CGRect
}

/// Coordinate conversion and window-to-display assignment. Pure functions over plain geometry.
enum DisplayGeometry {
    /// Two window areas closer than this (in square points) count as a tie.
    private static let areaTolerance: CGFloat = 1e-6

    /// The height `H` used to flip AppKit y values: the height of the display whose AppKit frame origin is
    /// (0, 0), else the `isMain` display, else the first display. `nil` for an empty layout.
    static func referenceHeight(for displays: [DisplayInfo]) -> CGFloat? {
        if let atOrigin = displays.first(where: { $0.frame.origin == .zero }) {
            return atOrigin.frame.height
        }
        if let main = displays.first(where: { $0.isMain }) {
            return main.frame.height
        }
        return displays.first?.frame.height
    }

    /// Converts an AppKit frame (bottom-left origin) to Quartz coordinates (top-left origin) given `H`.
    static func quartzFrame(fromAppKit frame: CGRect, referenceHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: referenceHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Every display of `layout` in Quartz coordinates, in layout order. Empty for an empty layout.
    static func quartzFrames(for layout: DisplayLayout) -> [QuartzDisplayFrame] {
        guard let height = referenceHeight(for: layout.displays) else { return [] }
        return layout.displays.map {
            QuartzDisplayFrame(id: $0.id, frame: quartzFrame(fromAppKit: $0.frame, referenceHeight: height))
        }
    }

    /// The display holding most of `bounds`: the largest intersection area wins. On a tie, the tied display
    /// that contains the window's center wins, and if none does, the first in layout order. `nil` when the
    /// window overlaps no display.
    static func assignedDisplay(for bounds: CGRect, in displays: [QuartzDisplayFrame]) -> DisplayID? {
        var best: [(display: QuartzDisplayFrame, area: CGFloat)] = []
        for display in displays {
            let overlap = display.frame.intersection(bounds)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if let current = best.first?.area {
                if area > current + areaTolerance {
                    best = [(display, area)]
                } else if area >= current - areaTolerance {
                    best.append((display, area))
                }
            } else {
                best = [(display, area)]
            }
        }
        guard let first = best.first else { return nil }
        if best.count > 1 {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if let containing = best.first(where: { $0.display.frame.contains(center) }) {
                return containing.display.id
            }
        }
        return first.display.id
    }
}
