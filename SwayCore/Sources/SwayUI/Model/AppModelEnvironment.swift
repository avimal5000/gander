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
    var notificationCenter: NotificationCenter
    /// How often the gate timer fires; `nil` disables the timer (tests call `AppModel.gateTick()` instead).
    var gateTickInterval: Duration?
    /// How often the Focus Test window's timer fires while it is open; `nil` disables the timer (tests call
    /// `AppModel.focusTick()` instead).
    var focusTickInterval: Duration?
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
            gateTickInterval: .milliseconds(100),
            focusTickInterval: .milliseconds(100),
            cameraStartTimeout: 10
        )
    }
}
