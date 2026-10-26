import Foundation
import Testing
import os

@testable import CameraService

/// Stands in for the distributed notification center: it records the selector-based registrations and removals and
/// never talks to the system (CONTRACT 12).
private final class RecordingDistributedCenter: DistributedNotificationCenter, @unchecked Sendable {
    // @unchecked Sendable: all state is behind `lock`.

    // @unchecked Sendable: immutable values, and the observer is only ever poked from the test's own thread.
    struct Registration: @unchecked Sendable {
        /// Weak, like the real center, which does not retain its observers.
        weak var observer: NSObject?
        let selector: Selector
        let name: Notification.Name?
        let object: String?
        let behavior: DistributedNotificationCenter.SuspensionBehavior
    }

    private struct State {
        var registrations: [Registration] = []
        var removals = 0
    }

    private let lock = OSAllocatedUnfairLock(uncheckedState: State())

    var registrations: [Registration] { lock.withLock { $0.registrations } }
    var removals: Int { lock.withLock { $0.removals } }

    override func addObserver(
        _ observer: Any,
        selector: Selector,
        name: NSNotification.Name?,
        object: String?,
        suspensionBehavior: DistributedNotificationCenter.SuspensionBehavior
    ) {
        guard let observer = observer as? NSObject else { return }
        let registration = Registration(
            observer: observer, selector: selector, name: name, object: object, behavior: suspensionBehavior)
        lock.withLock { $0.registrations.append(registration) }
    }

    override func removeObserver(_ observer: Any) {
        lock.withLock { $0.removals += 1 }
    }
}

private let lockName = Notification.Name("com.apple.screenIsLocked")
private let unlockName = Notification.Name("com.apple.screenIsUnlocked")

@Suite("Immediate distributed notification observer")
struct ImmediateDistributedObserverTests {
    @Test func registersForImmediateDelivery() {
        let center = RecordingDistributedCenter()
        let observe = ImmediateDistributedObserver.observation(on: center)
        let remove = observe(lockName) { _ in }
        defer { remove() }

        let registrations = center.registrations
        #expect(registrations.count == 1)
        #expect(registrations.first?.name == lockName)
        #expect(registrations.first?.behavior == .deliverImmediately)
        #expect(registrations.first?.object == nil)
    }

    @Test func theRegisteredSelectorDeliversTheNotificationToTheHandler() {
        let center = RecordingDistributedCenter()
        let received = OSAllocatedUnfairLock(initialState: [Notification.Name]())
        let remove = ImmediateDistributedObserver.observation(on: center)(unlockName) { notification in
            let name = notification.name
            received.withLock { $0.append(name) }
        }
        defer { remove() }

        guard let registration = center.registrations.first else {
            Issue.record("nothing was registered")
            return
        }
        _ = registration.observer?.perform(registration.selector, with: NSNotification(name: unlockName, object: nil))
        #expect(received.withLock { $0 } == [unlockName])
    }

    @Test func theReturnedFunctionRemovesTheRegistration() {
        let center = RecordingDistributedCenter()
        let remove = ImmediateDistributedObserver.observation(on: center)(lockName) { _ in }
        #expect(center.removals == 0)
        remove()
        #expect(center.removals == 1)
    }

    @Test func droppingTheObserverRemovesItToo() {
        let center = RecordingDistributedCenter()
        do {
            _ = ImmediateDistributedObserver.observation(on: center)(lockName) { _ in }
        }
        #expect(center.removals == 1)
    }

    /// The controller observes lock and unlock only through the injected registration, and with the live one that
    /// means both names are registered for immediate delivery.
    @Test func theControllerRegistersLockAndUnlockForImmediateDelivery() async throws {
        let center = RecordingDistributedCenter()
        let harness = ControllerHarness(observeDistributed: ImmediateDistributedObserver.observation(on: center))
        let registrations = center.registrations
        #expect(registrations.map(\.name) == [lockName, unlockName])
        #expect(registrations.allSatisfy { $0.behavior == .deliverImmediately })

        // A lock delivered through that registration suspends the next start.
        let lock = registrations[0]
        _ = lock.observer?.perform(lock.selector, with: NSNotification(name: lockName, object: nil))
        try await harness.start()
        await harness.controller.stop()
        #expect(harness.statuses == [.suspended(.screenLocked), .stopped])
        #expect(harness.sessionBuilds == 0)
    }
}
