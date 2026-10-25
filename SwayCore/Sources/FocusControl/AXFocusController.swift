import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The FocusControl builder replaces this file. See CONTRACT.md.

/// Last-used window per display and focus switching through the Accessibility API.
public final class AXFocusController: FocusControlling {
    public init() {}

    public func isTrusted() -> Bool { false }

    public func requestTrust() {}

    public func lastUsedWindows(in layout: DisplayLayout) async -> [DisplayID: WindowSummary] { [:] }

    public func focusedDisplay(in layout: DisplayLayout) async -> DisplayID? { nil }

    public func focus(display: DisplayID, in layout: DisplayLayout) async -> FocusResult { .notTrusted }
}
