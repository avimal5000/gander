import AppKit
import SwiftUI

/// Whether a window's live content should be drawn. Pure, so it is unit tested.
///
/// SwiftUI keeps a closed `Window` scene's (and the menu popover's) view hierarchy alive, and those views keep
/// updating with the model: a closed Pose Debug window redrew its plot for every camera frame. Views with live data
/// therefore draw it only while their window is on screen. Covered windows still count as shown, so nothing has to be
/// rebuilt (and flash) when they are uncovered.
enum WindowVisibility {
    static func showsLiveContent(isVisible: Bool, isMiniaturized: Bool, isClosing: Bool) -> Bool {
        isVisible && !isMiniaturized && !isClosing
    }
}

/// Reports whether the window holding this view shows live content (`WindowVisibility`), on every change.
///
/// Callers start out showing their content; only changes after that are reported, so a window that is still being
/// ordered in never blanks its first frame. Changes arrive on a later main-actor turn, never while SwiftUI is updating
/// views. Without a window (for example in an `ImageRenderer`) nothing is reported.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onChange: onChange)
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onChange = onChange
    }

    @MainActor
    final class ReaderView: NSView {
        var onChange: @MainActor (Bool) -> Void
        private var observers: [any NSObjectProtocol] = []
        /// Starts as `true`, the state every caller starts in.
        private var lastReported = true

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            removeObservers()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            observers = names.map { name in
                // Posted on the main thread by AppKit; the queue makes that explicit.
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    let isClosing = notification.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.windowChanged(isClosing: isClosing) }
                }
            }
            // Moved into a window after its old one hid it: show again if this one is up. Never blanks on attach.
            if !lastReported { windowChanged(isClosing: false) }
        }

        private func windowChanged(isClosing: Bool) {
            guard let window else { return }
            let shows = WindowVisibility.showsLiveContent(
                isVisible: window.isVisible, isMiniaturized: window.isMiniaturized, isClosing: isClosing)
            guard shows != lastReported else { return }
            lastReported = shows
            let onChange = onChange
            Task { @MainActor in onChange(shows) }
        }

        private func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
        }
    }
}
