import AppKit
import ApplicationServices
import FrontProcess
import GanderModels
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
                logger.debug("raise timed out; skipping main")
                return
            }
            let mainError = AXElementAccess.setTrue(kAXMainAttribute, on: handle.window.element)
            logger.debug("raise=\(raiseError.rawValue) main=\(mainError.rawValue)")
        }
    }

    func activateApplication(processID: Int32) async {
        let outcome = await FrontWindowActivation.run(
            frontWindowOnly: { await MainActor.run { GanderFrontWindowOnly(processID) } },
            becomesFrontmost: { await becomesFrontmost(processID, within: Self.frontWindowOnlyWait) },
            fallback: {
                await MainActor.run {
                    NSRunningApplication(processIdentifier: processID)?.activate(options: []) ?? false
                }
            }
        )
        switch outcome {
        case .frontWindowOnly:
            logger.debug("activation frontWindowOnly")
        case .cancelled:
            logger.debug("activation cancelled")
        case .fellBack(let status, let requested):
            // Info, not debug: a run of these means D53 stopped working, and scripts/soak.sh counts them.
            logger.info("activation fell back status=\(status) requested=\(requested)")
        }
    }

    /// How long front-window-only activation may take to bring the app to the front before the fallback.
    static let frontWindowOnlyWait: Duration = .milliseconds(100)

    /// True once `processID` is the frontmost app, checked every 10 ms for up to `wait`.
    private func becomesFrontmost(_ processID: Int32, within wait: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: wait)
        while true {
            let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            if frontmost == processID { return true }
            if clock.now >= deadline || Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func makeFrontmost(_ handle: LocatedWindow) async {
        let logger = logger
        await queue.run {
            let frontmostError = AXElementAccess.setTrue(kAXFrontmostAttribute, on: handle.app.element)
            logger.debug("frontmost=\(frontmostError.rawValue)")
        }
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
