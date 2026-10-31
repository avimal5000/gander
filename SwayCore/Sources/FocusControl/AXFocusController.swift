import AppKit
import ApplicationServices
import Foundation
import SwayModels
import os

/// Last-used window per display and focus switching through the Accessibility API.
///
/// The last-used window on a display is its topmost normal window in the window server's z-order. Focus moves
/// with public Accessibility and AppKit calls only and never moves the cursor. Every window-list and
/// Accessibility call runs on one private serial queue, never on the main thread.
public final class AXFocusController: FocusControlling {
    private let queue: SerialWorkQueue
    private let logger: Logger
    private let ownProcessID: Int32
    private let sequence: FocusSequence<LiveFocusPlatform>

    public init() {
        let queue = SerialWorkQueue(label: "\(SwayPolicy.bundleIdentifier).focus-control")
        let logger = SwayLog.logger(category: "focus")
        self.queue = queue
        self.logger = logger
        self.ownProcessID = ProcessInfo.processInfo.processIdentifier
        self.sequence = FocusSequence(platform: LiveFocusPlatform(queue: queue, logger: logger))
    }

    // MARK: Permission

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestTrust() {
        // "AXTrustedCheckOptionPrompt" is the documented value of kAXTrustedCheckOptionPrompt. The constant is
        // a mutable global that Swift 6 rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Queries

    public func lastUsedWindows(in layout: DisplayLayout) async -> [DisplayID: WindowSummary] {
        await currentWindows(in: layout, readTitles: isTrusted())
    }

    public func focusedDisplay(in layout: DisplayLayout) async -> DisplayID? {
        guard !layout.displays.isEmpty else { return nil }
        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard let frontmost, frontmost != ownProcessID else { return nil }
        let trusted = isTrusted()
        let ownProcessID = ownProcessID
        return await queue.run {
            let displays = DisplayGeometry.quartzFrames(for: layout)
            if trusted, let display = Self.focusedWindowDisplay(processID: frontmost, displays: displays) {
                return display
            }
            return LastUsedWindowSelector.frontmostWindow(
                ofProcess: frontmost,
                in: WindowServerList.currentRecords(),
                displays: displays,
                ownProcessID: ownProcessID
            )?.displayID
        }
    }

    // MARK: Focusing

    public func focus(display: DisplayID, in layout: DisplayLayout) async -> FocusResult {
        guard isTrusted() else {
            logger.info("focus outcome=notTrusted")
            return .notTrusted
        }
        let clock = ContinuousClock()
        let started = clock.now
        let windows = await currentWindows(in: layout, readTitles: false)
        guard let target = windows[display] else {
            logger.info("focus outcome=noWindow")
            return .noWindow(display)
        }
        let outcome = await sequence.run(target: target)
        let milliseconds = started.duration(to: clock.now).wholeMilliseconds
        let result = outcome.result(for: target, milliseconds: milliseconds)
        log(result, app: target.appName)
        return result
    }

    // MARK: Helpers

    /// Last-used windows for every display of `layout`. Titles are looked up through Accessibility only when
    /// `readTitles` is true.
    private func currentWindows(in layout: DisplayLayout, readTitles: Bool) async -> [DisplayID: WindowSummary] {
        guard !layout.displays.isEmpty else { return [:] }
        let ownProcessID = ownProcessID
        return await queue.run {
            let displays = DisplayGeometry.quartzFrames(for: layout)
            let selected = LastUsedWindowSelector.select(
                from: WindowServerList.currentRecords(),
                displays: displays,
                ownProcessID: ownProcessID
            )
            var windows: [DisplayID: WindowSummary] = [:]
            for (displayID, record) in selected {
                let title =
                    readTitles
                    ? AXWindowLocator.locate(
                        processID: record.processID,
                        bounds: record.bounds,
                        messagingTimeout: AXWindowLocator.lookupTimeout
                    )?.title
                    : nil
                windows[displayID] = WindowSummary(record: record, displayID: displayID, title: title)
            }
            return windows
        }
    }

    /// The display of `processID`'s Accessibility focused window, `nil` if it cannot be read.
    private static func focusedWindowDisplay(processID: Int32, displays: [QuartzDisplayFrame]) -> DisplayID? {
        let app = AXUIElementCreateApplication(processID)
        _ = AXUIElementSetMessagingTimeout(app, AXWindowLocator.lookupTimeout)
        guard let window = AXElementAccess.focusedWindow(of: app) else { return nil }
        _ = AXUIElementSetMessagingTimeout(window, AXWindowLocator.lookupTimeout)
        guard let frame = AXElementAccess.frame(of: window).frame else { return nil }
        return DisplayGeometry.assignedDisplay(for: frame, in: displays)
    }

    /// Logs the outcome, app name, method, and duration. Never the window title.
    private func log(_ result: FocusResult, app: String) {
        switch result {
        case .focused(_, let method, let milliseconds):
            logger.info(
                "focus outcome=focused app=\(app, privacy: .private(mask: .hash)) method=\(method.rawValue, privacy: .public) ms=\(milliseconds)"
            )
        case .failed(_, let reason):
            logger.info(
                "focus outcome=failed app=\(app, privacy: .private(mask: .hash)) reason=\(reason, privacy: .public)"
            )
        case .noWindow:
            logger.info("focus outcome=noWindow")
        case .notTrusted:
            logger.info("focus outcome=notTrusted")
        }
    }
}
