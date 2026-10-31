import AppKit
import Foundation
import GanderModels

/// The state behind one `AsyncStream<DisplayLayout>` returned by `ScreenDisplayTracker.layouts()`.
///
/// Each stream owns its own session, so streams never share a debounce timer or a "last yielded" value.
/// A session lives as long as its stream: the stream's termination handler holds it, and calls `stop()`.
@MainActor
final class LayoutChangeStream {
    /// Suspends for the given duration. Throws `CancellationError` when the surrounding task is cancelled.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let logger = GanderLog.logger(category: "displays")
    private let computeLayout: @MainActor () -> DisplayLayout
    private let notificationCenter: NotificationCenter
    private let debounce: Duration
    private let sleep: Sleep
    private let continuation: AsyncStream<DisplayLayout>.Continuation

    private var observer: (any NSObjectProtocol)?
    private var debounceTask: Task<Void, Never>?
    private var lastYielded: DisplayLayout?
    private var isStopped = false

    private init(
        computeLayout: @escaping @MainActor () -> DisplayLayout,
        notificationCenter: NotificationCenter,
        debounce: Duration,
        sleep: @escaping Sleep,
        continuation: AsyncStream<DisplayLayout>.Continuation
    ) {
        self.computeLayout = computeLayout
        self.notificationCenter = notificationCenter
        self.debounce = debounce
        self.sleep = sleep
        self.continuation = continuation
    }

    /// Creates a stream that yields the current layout immediately, then each distinct change after a debounce.
    ///
    /// Only the newest unconsumed layout is kept, so a slow consumer skips stale intermediate layouts.
    static func make(
        computeLayout: @escaping @MainActor () -> DisplayLayout,
        notificationCenter: NotificationCenter,
        debounce: Duration,
        sleep: @escaping Sleep
    ) -> AsyncStream<DisplayLayout> {
        let (stream, continuation) = AsyncStream<DisplayLayout>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let session = LayoutChangeStream(
            computeLayout: computeLayout,
            notificationCenter: notificationCenter,
            debounce: debounce,
            sleep: sleep,
            continuation: continuation
        )
        // Called when the consumer cancels, the stream is dropped, or the stream finishes. Termination can arrive
        // on any thread, so hop to the main actor where the session's state lives.
        continuation.onTermination = { _ in
            Task { @MainActor in session.stop() }
        }
        session.start()
        return stream
    }

    private func start() {
        observer = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // The block runs on the posting thread, so hop to the main actor.
            Task { @MainActor in self?.screenParametersDidChange() }
        }
        emit(computeLayout())
    }

    /// Cancels the debounce, removes the observer, and finishes the stream. Safe to call more than once.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        debounceTask?.cancel()
        debounceTask = nil
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        continuation.finish()
        logger.debug("Display layout stream stopped")
    }

    /// Restarts the debounce window. A burst of notifications therefore leads to a single recompute, after the
    /// last notification of the burst has been quiet for `debounce`.
    private func screenParametersDidChange() {
        guard !isStopped else { return }
        debounceTask?.cancel()
        let sleep = self.sleep
        let debounce = self.debounce
        debounceTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                try await sleep(debounce)
            } catch {
                return
            }
            // A superseded task can still wake normally if cancellation raced with the sleep, so check again.
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }

    private func recompute() {
        guard !isStopped else { return }
        emit(computeLayout())
    }

    /// Yields `layout` unless it equals the last value yielded on this stream.
    ///
    /// Comparison uses the whole layout, not just the fingerprint, so a changed `cgDisplayID` for the same
    /// physical arrangement (which the gate-test overlays rely on) still counts as a change.
    private func emit(_ layout: DisplayLayout) {
        guard layout != lastYielded else {
            logger.debug("Display layout unchanged, not yielding")
            return
        }
        lastYielded = layout
        logger.info("Display layout: \(layout.displays.count) display(s)")
        continuation.yield(layout)
    }
}
