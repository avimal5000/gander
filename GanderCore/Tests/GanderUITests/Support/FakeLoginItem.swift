import Foundation
import GanderModels

/// A login item that never calls `SMAppService`.
@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus = .disabled
    var error: LoginItemError?
    private(set) var setEnabledCalls: [Bool] = []
    private(set) var openSettingsCount = 0

    func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        setEnabledCalls.append(enabled)
        if let error { throw error }
        status = enabled ? .enabled : .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}
