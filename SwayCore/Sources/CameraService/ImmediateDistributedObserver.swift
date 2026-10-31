import Foundation

/// Receives one distributed notification and hands it to a handler, with immediate delivery.
///
/// `DistributedNotificationCenter` suspends delivery to an app that is not active, and the block-based
/// `addObserver(forName:...)` registers with the coalescing behavior, so a notification that arrives while Gander is in
/// the background (nearly always) may reach it late. The screen lock is such a notification, and a late lock would
/// leave the camera on at the lock screen. This registration uses `.deliverImmediately` instead, which only the
/// selector-based `addObserver` offers, hence an `NSObject`.
final class ImmediateDistributedObserver: NSObject, @unchecked Sendable {
    // @unchecked Sendable: NSObject is not Sendable, but both stored properties are immutable.

    private let center: DistributedNotificationCenter
    private let handler: @Sendable (Notification) -> Void

    /// Registers on `center` straight away. Delivery is on the main thread (the center's rule); the handler must
    /// only hop to the owner's queue.
    init(
        name: Notification.Name, center: DistributedNotificationCenter,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        self.handler = handler
        super.init()
        center.addObserver(
            self,
            selector: #selector(received(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        invalidate()
    }

    /// Stops delivery. Safe to call more than once.
    func invalidate() {
        center.removeObserver(self)
    }

    @objc private func received(_ notification: Notification) {
        handler(notification)
    }

    /// The registration `CaptureEnvironment` offers: one observer per name, removed by the returned function.
    static func observation(on center: DistributedNotificationCenter) -> DistributedObservation {
        { name, handler in
            let observer = ImmediateDistributedObserver(name: name, center: center, handler: handler)
            return { observer.invalidate() }
        }
    }
}
