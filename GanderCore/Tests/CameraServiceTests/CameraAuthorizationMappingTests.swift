import AVFoundation
import GanderModels
import Testing

@testable import CameraService

@Suite("Camera authorization and device type mapping")
struct CameraAuthorizationMappingTests {
    @Test func everyAVStatusMapsToTheMatchingAuthorization() {
        #expect(CameraAuthorizationMapper.map(.notDetermined) == .notDetermined)
        #expect(CameraAuthorizationMapper.map(.authorized) == .authorized)
        #expect(CameraAuthorizationMapper.map(.denied) == .denied)
        #expect(CameraAuthorizationMapper.map(.restricted) == .restricted)
    }

    @Test func unknownFutureStatusIsNeverTreatedAsAuthorized() throws {
        let future = try #require(AVAuthorizationStatus(rawValue: 99))
        #expect(CameraAuthorizationMapper.map(future) != .authorized)
    }

    @Test func onlyTheBuiltInWideAngleTypeIsBuiltIn() {
        #expect(CameraDeviceCatalog.isBuiltIn(deviceType: .builtInWideAngleCamera, isContinuityCamera: false))
        #expect(!CameraDeviceCatalog.isBuiltIn(deviceType: .external, isContinuityCamera: false))
        #expect(!CameraDeviceCatalog.isBuiltIn(deviceType: .continuityCamera, isContinuityCamera: true))
    }

    @Test func aContinuityCameraReportedAsBuiltInIsNotBuiltIn() {
        // Without NSCameraUseContinuityCameraDeviceType in Info.plist, macOS reports an iPhone as built-in.
        #expect(!CameraDeviceCatalog.isBuiltIn(deviceType: .builtInWideAngleCamera, isContinuityCamera: true))
    }

    @Test func discoveryUsesTheThreeContractDeviceTypes() {
        #expect(
            CameraDeviceCatalog.discoveryDeviceTypes == [.builtInWideAngleCamera, .external, .continuityCamera])
    }
}
