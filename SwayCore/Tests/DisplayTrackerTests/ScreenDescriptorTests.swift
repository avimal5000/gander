import CoreGraphics
import SwayModels
import Testing

@testable import DisplayTracker

@Suite("ScreenDescriptor mapping")
struct ScreenDescriptorTests {
    @Test func mapsEveryFieldIntoDisplayInfo() {
        let frame = CGRect(x: -1440, y: 120, width: 1440, height: 900)
        let descriptor = ScreenDescriptor.fixture(
            cgDisplayID: 77,
            uuid: "11111111-2222-3333-4444-555555555555",
            name: "Studio Display",
            frame: frame,
            isBuiltIn: false,
            isMain: true
        )

        let info = descriptor.displayInfo

        #expect(info.id == DisplayID("11111111-2222-3333-4444-555555555555"))
        #expect(info.cgDisplayID == 77)
        #expect(info.name == "Studio Display")
        #expect(info.frame == frame)
        #expect(info.isBuiltIn == false)
        #expect(info.isMain == true)
    }

    @Test(arguments: [true, false], [true, false])
    func carriesBuiltInAndMainFlagsIndependently(isBuiltIn: Bool, isMain: Bool) {
        let info = ScreenDescriptor.fixture(isBuiltIn: isBuiltIn, isMain: isMain).displayInfo

        #expect(info.isBuiltIn == isBuiltIn)
        #expect(info.isMain == isMain)
    }

    @Test func missingUUIDFallsBackToCGDisplayIDName() {
        let info = ScreenDescriptor.fixture(cgDisplayID: 42, uuid: nil).displayInfo

        #expect(info.id == DisplayID("cg-42"))
        #expect(info.cgDisplayID == 42)
    }

    @Test func emptyUUIDFallsBackToCGDisplayIDName() {
        let info = ScreenDescriptor.fixture(cgDisplayID: 9, uuid: "").displayInfo

        #expect(info.id == DisplayID("cg-9"))
    }

    @Test func layoutSortsLeftToRightAndFingerprintsIDsAndFrames() {
        let right = ScreenDescriptor.fixture(
            cgDisplayID: 2,
            uuid: "B",
            frame: CGRect(x: 1920, y: 0, width: 1280, height: 720)
        )
        let left = ScreenDescriptor.fixture(
            cgDisplayID: 1,
            uuid: "A",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        let layout = ScreenDescriptor.layout(from: [right, left])

        #expect(layout.displays.map(\.id) == [DisplayID("A"), DisplayID("B")])
        #expect(layout.fingerprint == "A@0,0,1920x1080|B@1920,0,1280x720")
    }

    @Test func fingerprintIgnoresSessionScopedCGDisplayIDs() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let before = ScreenDescriptor.layout(from: [.fixture(cgDisplayID: 1, uuid: "A", frame: frame)])
        let after = ScreenDescriptor.layout(from: [.fixture(cgDisplayID: 99, uuid: "A", frame: frame)])

        #expect(before.fingerprint == after.fingerprint)
        // The layouts still differ: the overlays need the new cgDisplayID.
        #expect(before != after)
    }

    @Test func duplicateStableIDsAreDisambiguatedWithTheFallbackName() {
        let first = ScreenDescriptor.fixture(
            cgDisplayID: 10, uuid: "SAME", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let second = ScreenDescriptor.fixture(
            cgDisplayID: 11, uuid: "SAME", frame: CGRect(x: 100, y: 0, width: 100, height: 100))

        let layout = ScreenDescriptor.layout(from: [first, second])

        #expect(layout.displays.map(\.id) == [DisplayID("SAME"), DisplayID("cg-11")])
        #expect(Set(layout.displays.map(\.id)).count == 2)
    }

    @Test func noScreensGiveAnEmptyLayout() {
        #expect(ScreenDescriptor.layout(from: []) == DisplayLayout.empty)
    }
}
