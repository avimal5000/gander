import Foundation
import GanderModels

/// NSScreen-backed display layout tracking.
///
/// `currentLayout` reads `NSScreen.screens` on demand. Each `layouts()` call returns its own stream that yields
/// the current layout immediately and then each distinct change reported through
/// `NSApplication.didChangeScreenParametersNotification`, debounced by 0.5 s.
@MainActor
public final class ScreenDisplayTracker: DisplayProviding {
    /// How long the screen configuration must stay quiet before a change is read and compared.
    static let defaultDebounce: Duration = .milliseconds(500)

    private let screens: @MainActor () -> [ScreenDescriptor]
    private let notificationCenter: NotificationCenter
    private let debounce: Duration
    private let sleep: LayoutChangeStream.Sleep

    /// Creates a tracker over the real screens and the default notification center.
    public convenience init() {
        self.init(
            screens: { SystemScreens.current() },
            notificationCenter: .default,
            debounce: Self.defaultDebounce,
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    /// Creates a tracker over injected dependencies, for tests.
    ///
    /// - Parameters:
    ///   - screens: Supplies the screen descriptors each time the layout is read.
    ///   - notificationCenter: Where `didChangeScreenParametersNotification` is observed.
    ///   - debounce: The quiet period before a notification triggers a recompute.
    ///   - sleep: How the debounce waits. Tests replace it to control time.
    init(
        screens: @escaping @MainActor () -> [ScreenDescriptor],
        notificationCenter: NotificationCenter,
        debounce: Duration,
        sleep: @escaping LayoutChangeStream.Sleep
    ) {
        self.screens = screens
        self.notificationCenter = notificationCenter
        self.debounce = debounce
        self.sleep = sleep
    }

    public var currentLayout: DisplayLayout {
        ScreenDescriptor.layout(from: screens())
    }

    public func layouts() -> AsyncStream<DisplayLayout> {
        let screens = self.screens
        return LayoutChangeStream.make(
            computeLayout: { ScreenDescriptor.layout(from: screens()) },
            notificationCenter: notificationCenter,
            debounce: debounce,
            sleep: sleep
        )
    }
}
