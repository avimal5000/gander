import Testing

@testable import SystemIntegration

@Suite("System integration stub")
struct SystemIntegrationStubTests {
    @Test @MainActor func stubsExist() {
        _ = CarbonHotKeyCenter()
        _ = MainAppLoginItem()
    }
}
