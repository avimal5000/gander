import Testing

@testable import CameraService

@Suite("Capture format fallback")
struct CaptureFormatChooserTests {
    @Test func picksTheSmallestFormatAtLeast640Wide() {
        let formats = [
            VideoDimensions(width: 1920, height: 1080),
            VideoDimensions(width: 1280, height: 720),
            VideoDimensions(width: 960, height: 540),
            VideoDimensions(width: 320, height: 240),
        ]
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: formats) == 2)
    }

    @Test func exactly640IsEnough() {
        let formats = [VideoDimensions(width: 1280, height: 720), VideoDimensions(width: 640, height: 480)]
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: formats) == 1)
    }

    @Test func narrowFormatsOnlyMeansKeepTheDeviceDefault() {
        let formats = [VideoDimensions(width: 320, height: 240), VideoDimensions(width: 160, height: 120)]
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: formats) == nil)
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: []) == nil)
    }

    @Test func equalAreasKeepTheEarlierFormat() {
        let formats = [VideoDimensions(width: 800, height: 600), VideoDimensions(width: 800, height: 600)]
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: formats) == 0)
    }

    @Test func sixteenByNineAtTheMinimumWidthQualifies() {
        let formats = [VideoDimensions(width: 1280, height: 720), VideoDimensions(width: 640, height: 360)]
        #expect(CaptureFormatChooser.smallestSufficientIndex(among: formats) == 1)
    }
}
