import AppKit
import ApplicationServices
import Foundation
import GanderModels
import os

/// Last-used window per display and focus switching through the Accessibility API.
///
/// The last-used window on a display is its topmost normal window in the window server's z-order. Focus moves
/// with public Accessibility, AppKit and Carbon calls only (Carbon for front-window-only activation, SPEC D53) and
/// never moves the cursor. Every window-list and Accessibility call runs on one private serial queue, never on the
/// main thread.
public final class AXFocusController: FocusControlling {
    private let queue: SerialWorkQueue
    private let logger: Logger
    private let ownProcessID: Int32
    private let sequence: FocusSequence<LiveFocusPlatform>
    /// The last switch's follow-up checks, still waiting (SPEC D54). A new request cancels them.
    private let followUp = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    public init() {
        let queue = SerialWorkQueue(label: "\(GanderPolicy.bundleIdentifier).focus-control")
        let logger = GanderLog.logger(category: "focus")
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
        followUp.withLock { task in
            task?.cancel()
            task = nil
        }
        let clock = ContinuousClock()
        let started = clock.now
        // Checked fresh, not from the once-a-second poll: raising this display's last-used window would bring a
        // window from behind over the one in use (SPEC D52).
        if let current = await focusedWindow(showingOn: display, in: layout) {
            let milliseconds = started.duration(to: clock.now).wholeMilliseconds
            let result = FocusResult.focused(current, method: .alreadyFocused, milliseconds: milliseconds)
            log(result, app: current.appName)
            return result
        }
        let windows = await currentWindows(in: layout, readTitles: false)
        guard let target = windows[display] else {
            logger.info("focus outcome=noWindow")
            return .noWindow(display)
        }
        let outcome = await sequence.run(target: target)
        let milliseconds = started.duration(to: clock.now).wholeMilliseconds
        let result = outcome.result(for: target, milliseconds: milliseconds)
        log(result, app: target.appName)
        if case .focused = outcome {
            // In the background, so the next switch never waits for it.
            let check = Task { [self] in await keepFocus(on: target, in: layout) }
            followUp.withLock { task in
                task?.cancel()
                task = check
            }
        }
        return result
    }

    // MARK: Keeping focus

    /// When to look again after a verified switch. Terminal moved focus within about 60 ms.
    static let keepFocusChecks: [Duration] = [.milliseconds(200), .milliseconds(300)]

    /// Puts focus back on `target` when its app moved focus to one of its windows on another display right after the
    /// switch (SPEC D54). Terminal, when activated, gives focus back to the window last typed in, often on another
    /// display; Gander then saw focus there and switched straight back. Focus that moved within the display is left
    /// alone: that is the user's new window (⌘N) or a sheet, and it cannot cause that bounce. So is everything once
    /// another app is in front.
    private func keepFocus(on target: WindowSummary, in layout: DisplayLayout) async {
        for delay in Self.keepFocusChecks {
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }
            let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            guard frontmost == target.processID else { return }
            let refocused = await queue.run {
                guard
                    let located = AXWindowLocator.locate(
                        processID: target.processID,
                        bounds: target.bounds,
                        messagingTimeout: AXWindowLocator.lookupTimeout
                    ),
                    let focused = AXElementAccess.focusedWindow(of: located.app.element),
                    !CFEqual(focused, located.window.element)
                else { return false }
                _ = AXUIElementSetMessagingTimeout(focused, AXWindowLocator.lookupTimeout)
                guard
                    KeepFocusCheck.focusLeftDisplay(
                        target.displayID,
                        focusedFrame: AXElementAccess.frame(of: focused).frame,
                        displays: DisplayGeometry.quartzFrames(for: layout)
                    )
                else { return false }
                _ = AXElementAccess.raise(located.window.element)
                AXElementAccess.setTrue(kAXMainAttribute, on: located.window.element)
                return true
            }
            if refocused {
                logger.info(
                    "focus kept: \(target.appName, privacy: .private(mask: .hash)) moved focus to another display"
                )
            }
        }
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

    /// The frontmost app's focused window when it already shows on `display` (SPEC D52); `nil` when it does not,
    /// when Gander itself is in front, or when the window cannot be found.
    private func focusedWindow(showingOn display: DisplayID, in layout: DisplayLayout) async -> WindowSummary? {
        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard let frontmost, frontmost != ownProcessID else { return nil }
        let ownProcessID = ownProcessID
        return await queue.run {
            let displays = DisplayGeometry.quartzFrames(for: layout)
            guard
                let record = AlreadyFocusedCheck.focusedRecord(
                    on: display,
                    processID: frontmost,
                    focusedFrame: Self.focusedWindowFrame(processID: frontmost),
                    in: WindowServerList.currentRecords(),
                    displays: displays,
                    ownProcessID: ownProcessID
                )
            else { return nil }
            let assigned = DisplayGeometry.assignedDisplay(for: record.bounds, in: displays) ?? display
            return WindowSummary(record: record, displayID: assigned, title: nil)
        }
    }

    /// The display of `processID`'s Accessibility focused window, `nil` if it cannot be read.
    private static func focusedWindowDisplay(processID: Int32, displays: [QuartzDisplayFrame]) -> DisplayID? {
        focusedWindowFrame(processID: processID).flatMap { DisplayGeometry.assignedDisplay(for: $0, in: displays) }
    }

    /// The frame of `processID`'s Accessibility focused window, `nil` if it cannot be read.
    private static func focusedWindowFrame(processID: Int32) -> CGRect? {
        let app = AXUIElementCreateApplication(processID)
        _ = AXUIElementSetMessagingTimeout(app, AXWindowLocator.lookupTimeout)
        guard let window = AXElementAccess.focusedWindow(of: app) else { return nil }
        _ = AXUIElementSetMessagingTimeout(window, AXWindowLocator.lookupTimeout)
        return AXElementAccess.frame(of: window).frame
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
