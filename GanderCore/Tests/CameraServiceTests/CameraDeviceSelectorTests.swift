import GanderModels
import Testing

@testable import CameraService

@Suite("Camera device selection")
struct CameraDeviceSelectorTests {
    private let builtIn = CameraDevice(id: "built-in", name: "FaceTime HD Camera", isBuiltIn: true)
    private let secondBuiltIn = CameraDevice(id: "built-in-2", name: "Other Built-in", isBuiltIn: true)
    private let external = CameraDevice(id: "usb-c922", name: "C922 Pro Stream Webcam", isBuiltIn: false)
    private let phone = CameraDevice(id: "phone", name: "iPhone Camera", isBuiltIn: false)

    @Test func connectedPreferredDeviceWins() throws {
        let choice = try CameraDeviceSelector.select(
            preferredID: "usb-c922", devices: [builtIn, external], systemDefault: builtIn)
        #expect(choice.device == external)
        #expect(choice.reason == .preferred)
        #expect(!choice.preferredWasUnavailable)
    }

    @Test func noPreferenceSelectsFirstBuiltIn() throws {
        let choice = try CameraDeviceSelector.select(
            preferredID: nil, devices: [external, builtIn, secondBuiltIn], systemDefault: external)
        #expect(choice.device == builtIn)
        #expect(choice.reason == .builtIn)
        #expect(!choice.preferredWasUnavailable)
    }

    @Test func unknownPreferredFallsBackToBuiltInAndIsFlagged() throws {
        let choice = try CameraDeviceSelector.select(
            preferredID: "gone", devices: [external, builtIn], systemDefault: external)
        #expect(choice.device == builtIn)
        #expect(choice.reason == .builtIn)
        #expect(choice.preferredWasUnavailable)
    }

    @Test func withoutBuiltInTheSystemDefaultIsUsed() throws {
        let choice = try CameraDeviceSelector.select(
            preferredID: nil, devices: [external, phone], systemDefault: phone)
        #expect(choice.device == phone)
        #expect(choice.reason == .systemDefault)
    }

    @Test func systemDefaultNotListedByDiscoveryStillCounts() throws {
        let deskView = CameraDevice(id: "desk-view", name: "Desk View", isBuiltIn: false)
        let choice = try CameraDeviceSelector.select(preferredID: nil, devices: [], systemDefault: deskView)
        #expect(choice.device == deskView)
        #expect(choice.reason == .systemDefault)
    }

    @Test func preferredIDMatchingAnUnlistedSystemDefaultIsConnected() throws {
        let deskView = CameraDevice(id: "desk-view", name: "Desk View", isBuiltIn: false)
        let choice = try CameraDeviceSelector.select(
            preferredID: "desk-view", devices: [builtIn], systemDefault: deskView)
        #expect(choice.device == deskView)
        #expect(choice.reason == .preferred)
    }

    @Test func noDevicesAtAllThrowsNoDevice() {
        #expect(throws: CameraError.noDevice) {
            try CameraDeviceSelector.select(preferredID: nil, devices: [], systemDefault: nil)
        }
        #expect(throws: CameraError.noDevice) {
            try CameraDeviceSelector.select(preferredID: "anything", devices: [], systemDefault: nil)
        }
    }

    @Test func externalOnlySetupUsesTheSystemDefault() throws {
        // A Mac without a built-in camera (for example a Mac mini with a webcam) falls through to the default.
        let choice = try CameraDeviceSelector.select(preferredID: nil, devices: [external], systemDefault: external)
        #expect(choice.device == external)
        #expect(choice.reason == .systemDefault)
    }

    @Test func emptyPreferredIDIsTreatedAsUnknown() throws {
        let choice = try CameraDeviceSelector.select(preferredID: "", devices: [builtIn], systemDefault: builtIn)
        #expect(choice.device == builtIn)
        #expect(choice.preferredWasUnavailable)
    }
}
