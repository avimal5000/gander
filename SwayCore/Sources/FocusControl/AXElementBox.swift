import ApplicationServices

/// Carries an `AXUIElement` across concurrency domains. This is the only place an AX reference crosses threads.
///
/// `@unchecked Sendable`: immutable CF reference; these AX calls are thread-safe. In practice every call on
/// the element still runs on the controller's single serial queue.
struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}
