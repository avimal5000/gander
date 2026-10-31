import GanderModels
import Testing

@testable import FocusControl

/// Safe smoke tests only. `requestTrust()` and `focus(display:in:)` are never called here: the test runner may
/// hold Accessibility permission, and a focus call would really move the user's focus.
@Suite struct AXFocusControllerTests {
    @Test func isTrustedReturnsWithoutPrompting() {
        let controller = AXFocusController()
        _ = controller.isTrusted()
    }

    @Test func lastUsedWindowsInAnEmptyLayoutIsEmpty() async {
        let controller = AXFocusController()
        let windows = await controller.lastUsedWindows(in: .empty)
        #expect(windows.isEmpty)
    }
}
