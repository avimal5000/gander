import CoreGraphics
import Testing

@testable import FocusControl

@Suite struct NormalWindowFilterTests {
    private let ownPID: Int32 = 555

    private func isNormal(_ record: WindowRecord) -> Bool {
        NormalWindowFilter.isNormal(record, ownProcessID: ownPID)
    }

    @Test func acceptsAnOrdinaryWindow() {
        #expect(isNormal(FocusFixtures.record()))
    }

    @Test(arguments: [-1, 1, 3, 20, 25])
    func rejectsNonZeroLayers(layer: Int) {
        #expect(!isNormal(FocusFixtures.record(layer: layer)))
    }

    @Test func rejectsInvisibleWindows() {
        #expect(!isNormal(FocusFixtures.record(alpha: 0)))
        #expect(!isNormal(FocusFixtures.record(alpha: 0.01)))
        #expect(isNormal(FocusFixtures.record(alpha: 0.02)))
    }

    @Test func rejectsWindowsSmallerThanTheMinimum() {
        #expect(!isNormal(FocusFixtures.record(bounds: CGRect(x: 0, y: 0, width: 119, height: 600))))
        #expect(!isNormal(FocusFixtures.record(bounds: CGRect(x: 0, y: 0, width: 800, height: 79))))
    }

    @Test func acceptsWindowsExactlyAtTheMinimum() {
        #expect(isNormal(FocusFixtures.record(bounds: CGRect(x: 0, y: 0, width: 120, height: 80))))
    }

    @Test func rejectsSwaysOwnWindows() {
        #expect(!isNormal(FocusFixtures.record(processID: ownPID)))
        #expect(isNormal(FocusFixtures.record(processID: ownPID + 1)))
    }

    @Test(arguments: ["Window Server", "Dock", "WindowManager"])
    func rejectsSystemOwners(owner: String) {
        #expect(!isNormal(FocusFixtures.record(ownerName: owner)))
    }

    @Test func acceptsAWindowWithAnEmptyOwnerName() {
        #expect(isNormal(FocusFixtures.record(ownerName: "")))
    }
}
