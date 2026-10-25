import ServiceManagement
import SwayModels
import Testing

@testable import SystemIntegration

@Suite struct LoginItemMappingTests {
    @Test func enabledMapsToEnabled() {
        #expect(LoginItemMapping.status(for: .enabled) == .enabled)
    }

    @Test func requiresApprovalMapsToRequiresApproval() {
        #expect(LoginItemMapping.status(for: .requiresApproval) == .requiresApproval)
    }

    @Test func notRegisteredMapsToDisabled() {
        #expect(LoginItemMapping.status(for: .notRegistered) == .disabled)
    }

    @Test func notFoundExplainsHowToFixIt() {
        let expected =
            "macOS can't find this copy of Sway. Move Sway to the Applications folder, open it from there, and try again."
        #expect(LoginItemMapping.status(for: .notFound) == .unavailable(expected))
    }

    @Test func unknownStateIsUnavailable() {
        #expect(LoginItemMapping.status(for: .unknown) == .unavailable("macOS reported an unknown login item state."))
    }

    @Test func systemStatusesMirrorOneToOne() {
        #expect(LoginItemSystemState(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemSystemState(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemSystemState(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemSystemState(SMAppService.Status.notFound) == .notFound)
    }

    @Test func failureMessageNamesTheActionAndIncludesTheSystemDescription() {
        let turnOn = LoginItemMapping.failureMessage(enabling: true, systemDescription: "Operation not permitted")
        #expect(turnOn == "Sway couldn't turn on opening at login. macOS said: Operation not permitted.")
        let turnOff = LoginItemMapping.failureMessage(enabling: false, systemDescription: "Job not found.")
        #expect(turnOff == "Sway couldn't turn off opening at login. macOS said: Job not found.")
    }

    @Test func failureMessageHandlesBlankDescriptions() {
        #expect(
            LoginItemMapping.failureMessage(enabling: true, systemDescription: "  \n")
                == "Sway couldn't turn on opening at login.")
    }
}
