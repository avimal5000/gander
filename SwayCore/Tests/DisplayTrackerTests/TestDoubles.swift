import AppKit
import CoreGraphics
import Foundation
import SwayModels
import os

@testable import DisplayTracker

extension ScreenDescriptor {
    /// A descriptor with sensible defaults. Every field can be overridden.
    static func fixture(
        cgDisplayID: UInt32 = 1,
        uuid: String? = "UUID-1",
        name: String = "Display 1",
        frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
        isBuiltIn: Bool = false,
        isMain: Bool = false
    ) -> ScreenDescriptor {
        ScreenDescriptor(
            cgDisplayID: cgDisplayID,
            uuidString: uuid,
            name: name,
            frame: frame,
            isBuiltIn: isBuiltIn,
            isMain: isMain
        )
    }
}

/// A screen source the test can change between reads. Counts reads so tests can see recomputes.
@MainActor
final class FakeScreens {
    var descriptors: [ScreenDescriptor]
    private(set) var readCount = 0

    init(_ descriptors: [ScreenDescriptor]) {
        self.descriptors = descriptors
    }

    func read() -> [ScreenDescriptor] {
        readCount += 1
        return descriptors
    }
}

/// A debounce sleep that never finishes by itself. Tests release it with `fireAll()`.
@MainActor
final class ManualSleeper {
    private var nextID = 0
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private(set) var startedCount = 0
    private(set) var lastDuration: Duration?

    /// Sleeps that have started and are neither fired nor cancelled yet.
    var pendingCount: Int { waiters.count }

    func sleep(_ duration: Duration) async throws {
        startedCount += 1
        lastDuration = duration
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    /// Lets every pending sleep return normally, as if its time had elapsed.
    func fireAll() {
        let pending = waiters
        waiters = [:]
        for continuation in pending.values {
            continuation.resume()
        }
    }

    private func cancelWaiter(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

/// A notification center that counts how many observers are currently registered.
final class CountingNotificationCenter: NotificationCenter, @unchecked Sendable {
    // Protected by the lock; the superclass is thread-safe, so the subclass must be as well.
    private let observers = OSAllocatedUnfairLock<Int>(initialState: 0)

    var observerCount: Int { observers.withLock { $0 } }

    override func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol {
        observers.withLock { $0 += 1 }
        return super.addObserver(forName: name, object: obj, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        observers.withLock { $0 -= 1 }
        super.removeObserver(observer)
    }
}

/// Consumes a layout stream in a task and records what it yields.
@MainActor
final class LayoutCollector {
    private(set) var layouts: [DisplayLayout] = []
    private(set) var isFinished = false
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<DisplayLayout>) {
        task = Task { [weak self] in
            for await layout in stream {
                self?.layouts.append(layout)
            }
            self?.isFinished = true
        }
    }

    /// Stops consuming, which terminates the stream the way a cancelled consumer would.
    func cancel() {
        task?.cancel()
    }
}

/// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
///
/// Polling is short (1 ms) so passing tests finish almost at once. The timeout only matters when a test fails.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

/// Gives pending main-actor work time to run, for assertions that something did *not* happen.
@MainActor
func settle() async {
    try? await Task.sleep(for: .milliseconds(15))
}

/// A tracker wired to fakes: fake screens, a private notification center, and a manual (or real) debounce sleep.
@MainActor
struct TrackerFixture {
    let screens: FakeScreens
    let center = CountingNotificationCenter()
    let sleeper = ManualSleeper()
    let tracker: ScreenDisplayTracker

    /// - Parameter realDebounce: When set, the tracker debounces with a real sleep of this length instead of
    ///   the manual sleeper.
    init(_ descriptors: [ScreenDescriptor], realDebounce: Duration? = nil) {
        let screens = FakeScreens(descriptors)
        self.screens = screens
        let sleeper = self.sleeper
        if let realDebounce {
            tracker = ScreenDisplayTracker(
                screens: { screens.read() },
                notificationCenter: center,
                debounce: realDebounce,
                sleep: { try await Task.sleep(for: $0) }
            )
        } else {
            tracker = ScreenDisplayTracker(
                screens: { screens.read() },
                notificationCenter: center,
                debounce: .milliseconds(500),
                sleep: { try await sleeper.sleep($0) }
            )
        }
    }

    /// Posts what AppKit posts when the screen configuration changes.
    func postScreenChange() {
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Releases pending debounce sleeps until `condition` holds. Firing repeatedly is harmless: sleeps from
    /// superseded notifications are cancelled and must not cause a recompute.
    func fireUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
        await waitUntil(timeout: timeout) {
            sleeper.fireAll()
            return condition()
        }
    }
}
