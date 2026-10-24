import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The DisplayTracker builder replaces this file. See CONTRACT.md.

/// NSScreen-backed display layout tracking.
@MainActor
public final class ScreenDisplayTracker: DisplayProviding {
    public init() {}

    public var currentLayout: DisplayLayout { .empty }

    public func layouts() -> AsyncStream<DisplayLayout> {
        AsyncStream { $0.finish() }
    }
}
