import CoreGraphics
import Foundation
import Testing

@testable import GanderModels

private func display(_ id: String, x: CGFloat, y: CGFloat = 0, cg: UInt32 = 1) -> DisplayInfo {
    DisplayInfo(
        id: DisplayID(id), cgDisplayID: cg, name: id,
        frame: CGRect(x: x, y: y, width: 1000, height: 600), isBuiltIn: false, isMain: false)
}

@Suite struct DisplayLayoutTests {
    @Test func sortsLeftToRight() {
        let layout = DisplayLayout(displays: [display("B", x: 1000), display("A", x: -1000), display("C", x: 0)])
        #expect(layout.displays.map(\.id.rawValue) == ["A", "C", "B"])
    }

    @Test func fingerprintIgnoresInputOrderAndRuntimeIDs() {
        let first = DisplayLayout(displays: [display("A", x: 0, cg: 1), display("B", x: 1000, cg: 2)])
        let second = DisplayLayout(displays: [display("B", x: 1000, cg: 7), display("A", x: 0, cg: 9)])
        #expect(first.fingerprint == second.fingerprint)
    }

    @Test func fingerprintChangesWhenArrangementChanges() {
        let before = DisplayLayout(displays: [display("A", x: 0), display("B", x: 1000)])
        let after = DisplayLayout(displays: [display("A", x: 0), display("B", x: -1000)])
        #expect(before.fingerprint != after.fingerprint)
    }

    @Test func lookupByID() {
        let layout = DisplayLayout(displays: [display("A", x: 0)])
        #expect(layout.display(withID: "A")?.name == "A")
        #expect(layout.display(withID: "Z") == nil)
    }
}

@Suite struct CodableTests {
    @Test func poseTraceRoundTrips() throws {
        let pose = HeadPose(
            yaw: 12.5, pitch: -3, roll: 1, faceConfidence: 0.9,
            faceBounds: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4), landmarkYaw: 10, landmarkPitch: nil)
        let trace = PoseTrace(
            cameraName: "Test Cam",
            layout: DisplayLayout(displays: [display("A", x: 0)]),
            segments: [
                TraceSegment(
                    displayID: "A", round: 1,
                    samples: [PoseSample(timestamp: 1, pose: pose), PoseSample(timestamp: 2, pose: nil)])
            ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PoseTrace.self, from: encoder.encode(trace))
        #expect(decoded.segments == trace.segments)
        #expect(decoded.layout == trace.layout)
        #expect(decoded.formatVersion == PoseTrace.currentFormatVersion)
    }
}

@Suite struct GateVerdictTests {
    @Test func ordering() {
        #expect(GateVerdict.insufficientData < .noGo)
        #expect(GateVerdict.noGo < .marginal)
        #expect(GateVerdict.marginal < .go)
        #expect([GateVerdict.noGo, .go, .marginal].max() == .go)
    }

    @Test func faceDetectionRate() {
        let stats = DisplayPoseStats(
            displayID: "A", displayName: "A", frameCount: 10, faceCount: 9, meanX: 0, meanY: 0, stdX: 1, stdY: 1)
        #expect(stats.faceDetectionRate == 0.9)
        let empty = DisplayPoseStats(
            displayID: "A", displayName: "A", frameCount: 0, faceCount: 0, meanX: 0, meanY: 0, stdX: 0, stdY: 0)
        #expect(empty.faceDetectionRate == 0)
    }
}
