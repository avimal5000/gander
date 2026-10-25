import CoreGraphics
import Foundation
import SwayModels
import Testing

@testable import DisplayTracker

/// Runs against whatever screens the machine has (none, one virtual display, or several), so it asserts only
/// invariants and never a screen count.
@Suite("SystemScreens")
@MainActor
struct SystemScreensTests {
    @Test func descriptorsFormALayoutWithUniqueIDs() {
        let descriptors = SystemScreens.current()
        let layout = ScreenDescriptor.layout(from: descriptors)

        #expect(layout.displays.count == descriptors.count)
        #expect(Set(layout.displays.map(\.id)).count == layout.displays.count)
    }

    @Test func trackerCurrentLayoutMatchesTheDescriptorMapping() {
        let layout = ScreenDisplayTracker().currentLayout

        #expect(layout.displays.map(\.cgDisplayID).sorted() == SystemScreens.current().map(\.cgDisplayID).sorted())
    }

    @Test func displayUUIDStringIsAParsableUUIDWhenAvailable() {
        // CI may have no main display at all, in which case there is nothing to check.
        guard let string = SystemScreens.uuidString(for: CGMainDisplayID()) else { return }

        #expect(UUID(uuidString: string) != nil)
    }
}
