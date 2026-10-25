import AppKit
import ApplicationServices
import SwayModels
import os

/// The real system behind the focus sequence: window-server, Accessibility, and AppKit calls. Accessibility
/// work runs on the shared serial queue; AppKit reads hop to the main actor.
final class LiveFocusPlatform: FocusPlatform {
    private let queue: SerialWorkQueue
    private let logger: Logger

    init(queue: SerialWorkQueue, logger: Logger) {
        self.queue = queue
        self.logger = logger
    }

    func prepare(_ target: WindowSummary) async -> LocatedWindow? {
        let processID = target.processID
        let bounds = target.bounds
        return await queue.run {
            AXWindowLocator.locate(processID: processID, bounds: bounds, messagingTimeout: AXWindowLocator.focusTimeout)
        }
    }

    func title(of handle: LocatedWindow) -> String? {
        handle.title
    }

    func raise(_ handle: LocatedWindow) async {
        let logger = logger
        await queue.run {
            let raiseError = AXElementAccess.raise(handle.window.element)
            guard raiseError != .cannotComplete else {
                logger.debug("raise timed out; skipping main and frontmost")
                return
            }
            let mainError = AXElementAccess.setTrue(kAXMainAttribute, on: handle.window.element)
            let frontmostError = AXElementAccess.setTrue(kAXFrontmostAttribute, on: handle.app.element)
            logger.debug(
                "raise=\(raiseError.rawValue) main=\(mainError.rawValue) frontmost=\(frontmostError.rawValue)"
            )
        }
    }

    func activateApplication(processID: Int32) async {
        let requested = await MainActor.run {
            NSRunningApplication(processIdentifier: processID)?.activate(from: .current, options: []) ?? false
        }
        logger.debug("activation requested=\(requested)")
    }

    func isFocused(_ handle: LocatedWindow) async -> Bool {
        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        var focusedWindowMatches: Bool?
        if frontmost == handle.processID {
            focusedWindowMatches = await queue.run {
                AXElementAccess.focusedWindow(of: handle.app.element).map { CFEqual($0, handle.window.element) }
            }
        }
        return FocusVerification.isVerified(
            frontmostProcessID: frontmost,
            targetProcessID: handle.processID,
            focusedWindowMatches: focusedWindowMatches
        )
    }
}
