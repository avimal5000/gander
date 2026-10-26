import Foundation

/// Whether the app counts as the active app, and whether motion is reduced, for the environment's closures.
@MainActor
final class FakeAppState {
    var isActive = false
    /// Whether the system asks for Reduce Motion, for `AppModelEnvironment.reduceMotion`.
    var reduceMotion = false
}
