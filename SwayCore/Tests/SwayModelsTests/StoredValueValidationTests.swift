import CoreGraphics
import Foundation
import Testing

@testable import SwayModels

/// Security audit S2, S9, S10: values read from disk or settings must not trap or poison tracking.
@Suite("Stored value validation")
struct StoredValueValidationTests {
    @Test(arguments: [1e300, -1e300, Double.infinity, -Double.infinity, Double.nan])
    func safeIntConversionNeverTraps(value: Double) {
        let result = Int(clamping: value)
        if value.isNaN {
            #expect(result == 0)
        } else {
            #expect(abs(result) == Int(Int.safeDoubleLimit))
            #expect((result > 0) == (value > 0))
        }
        #expect(Int(clamping: 12.6) == 13)
        #expect(Int(clamping: CGFloat(-3.4)) == -3)
    }

    @Test func layoutWithHugeFramesBuildsAFingerprint() {
        let display = DisplayInfo(
            id: "A", cgDisplayID: 1, name: "A", frame: CGRect(x: 1e300, y: -1e300, width: 1e300, height: 1e300),
            isBuiltIn: false, isMain: true)
        #expect(DisplayLayout(displays: [display]).fingerprint.hasPrefix("A@"))
    }

    private func profile(yawScale: Double, pitchScale: Double, yaw: Double = 0, count: Int = 60) -> CalibrationProfile {
        CalibrationProfile(
            features: .visionAngles,
            displays: ["A", "B"].map {
                DisplayProfile(displayID: DisplayID($0), yaw: yaw, pitch: 0, yawStd: 1, pitchStd: 1, sampleCount: count)
            },
            yawScale: yawScale, pitchScale: pitchScale, layoutFingerprint: "x", cameraName: nil,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func goodProfileIsUsable() {
        #expect(profile(yawScale: 1.5, pitchScale: 2.5).isUsable)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func badScalesAreRejected(scale: Double) {
        #expect(!profile(yawScale: scale, pitchScale: 2.5).isUsable)
        #expect(!profile(yawScale: 1.5, pitchScale: scale).isUsable)
        var library = CalibrationLibrary()
        library.save(profile(yawScale: scale, pitchScale: 2.5))
        #expect(library.profiles.isEmpty)
    }

    @Test func nonFiniteMeansAreRejected() {
        #expect(!profile(yawScale: 1, pitchScale: 1, yaw: .nan).isUsable)
        #expect(!profile(yawScale: 1, pitchScale: 1, yaw: .infinity).isUsable)
        #expect(!profile(yawScale: 1, pitchScale: 1, count: -1).isUsable)
    }

    @Test func storedLibraryWithAZeroScaleProfileFallsBackToTheGoodOnes() throws {
        var library = CalibrationLibrary()
        library.save(profile(yawScale: 1.5, pitchScale: 2.5))
        let data = try JSONEncoder().encode(library)
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"yawScale\":1.5", with: "\"yawScale\":0")
        let decoded = try JSONDecoder().decode(CalibrationLibrary.self, from: Data(json.utf8))
        #expect(json.contains("\"yawScale\":0"))
        #expect(decoded.profiles.isEmpty)
    }

    @Test func nonFiniteSensitivityFallsBackToTheDefault() {
        let sensitivity = SwitchSensitivity(dwell: .nan, cooldown: .infinity, confidenceLevel: 2)
        #expect(sensitivity.dwell == 0.40)
        #expect(sensitivity.cooldown == 0.75)
        #expect(SwitchSensitivity(dwell: -.infinity, cooldown: -.nan, confidenceLevel: 9).dwell == 0.40)
    }
}
