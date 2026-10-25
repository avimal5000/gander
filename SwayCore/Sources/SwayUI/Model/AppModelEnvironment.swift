import AppKit
import Foundation

/// The non-protocol collaborators of `AppModel`: time, desktop integration, overlays, notifications, timers. Tests
/// supply fakes; the app uses `live()`.
struct AppModelEnvironment {
    /// Monotonic seconds, used by the gate state machine and the Focus Test countdown and polling.
    var clock: GateClock
    /// Wall-clock time stamped on new traces.
    var now: @Sendable () -> Date
    var system: any SystemInteracting
    var overlay: any GateOverlayPresenting
    /// Where `NSApplication` posts become-active, resign-active, and will-terminate, and `NSWindow` posts key-window
    /// changes.
    var notificationCenter: NotificationCenter
    /// Where `NSWorkspace` posts app activations (a separate center from `notificationCenter`).
    var workspaceNotificationCenter: NotificationCenter
    /// Whether Sway is in front right now: the active app with a key window (its menu or one of its windows). Read at
    /// launch and again on every activation and key-window change.
    var isAppActive: @MainActor () -> Bool
    /// How often the gate timer fires; `nil` disables the timer (tests call `AppModel.gateTick()` instead).
    var gateTickInterval: Duration?
    /// How often the Focus Test window's timer fires while it is open; `nil` disables the timer (tests call
    /// `AppModel.focusTick()` instead).
    var focusTickInterval: Duration?
    /// How often the focused display is polled while tracking runs (SPEC D29); `nil` disables the timer (tests call
    /// `AppModel.trackingTick()` instead).
    var trackingTickInterval: Duration?
    /// How often the Setup window re-reads the camera and Accessibility permissions while it waits for one; `nil`
    /// disables the timer (tests call `AppModel.setupTick()` instead).
    var setupTickInterval: Duration?
    /// Delivers key presses to the Focus Lock shortcut recorder, only while it records.
    var keyMonitor: any ShortcutKeyMonitoring
    /// How long the camera may take to start before a gate test gives up.
    var cameraStartTimeout: TimeInterval

    @MainActor
    static func live() -> AppModelEnvironment {
        AppModelEnvironment(
            clock: { ProcessInfo.processInfo.systemUptime },
            now: { Date() },
            system: AppKitSystemInteractions(),
            overlay: GateOverlayController(),
            notificationCenter: .default,
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            // Active with no key window (its last window just closed) doesn't count: nothing of Sway's is in front,
            // and the user would be stuck until they clicked another app.
            isAppActive: { NSApplication.shared.isActive && NSApplication.shared.keyWindow != nil },
            gateTickInterval: .milliseconds(100),
            focusTickInterval: .milliseconds(100),
            trackingTickInterval: .seconds(AppModel.focusedDisplayPollInterval),
            setupTickInterval: .seconds(1),
            keyMonitor: LocalShortcutKeyMonitor(),
            cameraStartTimeout: 10
        )
    }
}
