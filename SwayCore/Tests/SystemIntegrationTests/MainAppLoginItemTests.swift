import Foundation
import SwayModels
import Testing

@testable import SystemIntegration

/// Drives `MainAppLoginItem` through a fake service; the real `SMAppService` is never called (CONTRACT 12).
@Suite @MainActor struct MainAppLoginItemTests {
    private final class FakeService: LoginItemSystemService {
        struct Failure: LocalizedError {
            var errorDescription: String? { "Operation not permitted" }
        }

        var state: LoginItemSystemState = .notRegistered
        var failure: (any Error)?
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0
        private(set) var openSettingsCalls = 0

        func register() throws {
            registerCalls += 1
            if let failure { throw failure }
        }

        func unregister() throws {
            unregisterCalls += 1
            if let failure { throw failure }
        }

        func openSystemSettings() {
            openSettingsCalls += 1
        }
    }

    @Test func statusIsReadFreshFromTheService() {
        let service = FakeService()
        let item = MainAppLoginItem(service: service)
        #expect(item.status == .disabled)
        service.state = .enabled
        #expect(item.status == .enabled)
        service.state = .requiresApproval
        #expect(item.status == .requiresApproval)
    }

    @Test func enablingRegistersOnly() throws {
        let service = FakeService()
        let item = MainAppLoginItem(service: service)
        try item.setEnabled(true)
        #expect(service.registerCalls == 1)
        #expect(service.unregisterCalls == 0)
    }

    @Test func disablingUnregistersOnly() throws {
        let service = FakeService()
        service.state = .enabled
        let item = MainAppLoginItem(service: service)
        try item.setEnabled(false)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 1)
    }

    @Test func registerFailureBecomesALoginItemErrorWithTheSystemDescription() {
        let service = FakeService()
        service.failure = FakeService.Failure()
        let item = MainAppLoginItem(service: service)
        do {
            try item.setEnabled(true)
            Issue.record("Expected a LoginItemError")
        } catch {
            #expect(error.message == "Sway couldn't turn on opening at login. macOS said: Operation not permitted.")
        }
    }

    @Test func unregisterFailureBecomesALoginItemErrorWithTheSystemDescription() {
        let service = FakeService()
        service.state = .requiresApproval
        service.failure = FakeService.Failure()
        let item = MainAppLoginItem(service: service)
        do {
            try item.setEnabled(false)
            Issue.record("Expected a LoginItemError")
        } catch {
            #expect(error.message.contains("turn off"))
            #expect(error.message.contains("Operation not permitted"))
        }
    }

    @Test func askingForTheCurrentStateCallsNothing() throws {
        let service = FakeService()
        let item = MainAppLoginItem(service: service)
        try item.setEnabled(false)
        service.state = .enabled
        try item.setEnabled(true)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }

    @Test func disablingAnItemAwaitingApprovalUnregisters() throws {
        let service = FakeService()
        service.state = .requiresApproval
        try MainAppLoginItem(service: service).setEnabled(false)
        #expect(service.unregisterCalls == 1)
    }

    @Test func opensSystemSettingsThroughTheService() {
        let service = FakeService()
        MainAppLoginItem(service: service).openSystemSettings()
        #expect(service.openSettingsCalls == 1)
    }
}
