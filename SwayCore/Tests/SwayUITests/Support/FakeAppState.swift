import Foundation

/// Whether the app counts as the active app, for `AppModelEnvironment.isAppActive`.
@MainActor
final class FakeAppState {
    var isActive = false
}
