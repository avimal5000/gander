import CoreGraphics
import Foundation
import SwayModels

/// Sample displays, cameras, poses, and analyses shared by the tests.
enum Fixtures {
    static let left = DisplayInfo(
        id: "display-left", cgDisplayID: 11, name: "Left", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        isBuiltIn: true, isMain: true
    )
    static let right = DisplayInfo(
        id: "display-right", cgDisplayID: 12, name: "Right",
        frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isBuiltIn: false, isMain: false
    )
    static let far = DisplayInfo(
        id: "display-far", cgDisplayID: 13, name: "Far", frame: CGRect(x: 4480, y: 0, width: 1920, height: 1080),
        isBuiltIn: false, isMain: false
    )

    static let twoDisplays = DisplayLayout(displays: [left, right])
    static let threeDisplays = DisplayLayout(displays: [left, right, far])
    static let oneDisplay = DisplayLayout(displays: [left])

    static let builtInCamera = CameraDevice(id: "cam-builtin", name: "FaceTime HD Camera", isBuiltIn: true)
    static let externalCamera = CameraDevice(id: "cam-external", name: "Logitech C922", isBuiltIn: false)

    static func pose(
        yaw: Double = 0, pitch: Double = 0, landmarkYaw: Double? = nil, landmarkPitch: Double? = nil
    ) -> HeadPose {
        HeadPose(
            yaw: yaw, pitch: pitch, roll: 0, faceConfidence: 0.95,
            faceBounds: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            landmarkYaw: landmarkYaw, landmarkPitch: landmarkPitch
        )
    }

    static func sample(at time: TimeInterval, face: Bool = true, yaw: Double = 0, pitch: Double = 0) -> PoseSample {
        PoseSample(timestamp: time, pose: face ? pose(yaw: yaw, pitch: pitch) : nil)
    }

    /// A report with two displays whose clusters sit at `-offset` and `+offset` yaw.
    static func report(_ featureSet: PoseFeatureSet, verdict: GateVerdict, offset: Double = 20) -> SeparabilityReport {
        let leftStats = DisplayPoseStats(
            displayID: left.id, displayName: left.name, frameCount: 100, faceCount: 98,
            meanX: -offset, meanY: 0, stdX: 2, stdY: 1
        )
        let rightStats = DisplayPoseStats(
            displayID: right.id, displayName: right.name, frameCount: 100, faceCount: 97,
            meanX: offset, meanY: 0, stdX: 2, stdY: 1
        )
        return SeparabilityReport(
            featureSet: featureSet, displays: [leftStats, rightStats],
            pairs: [PairSeparation(first: left.id, second: right.id, meanDistance: 2 * offset, dPrime: 15)],
            accuracy: 0.99, verdict: verdict, notes: []
        )
    }

    /// An analysis whose best feature set is `best`; the other report is marginal.
    static func analysis(best: PoseFeatureSet = .visionAngles) -> GateAnalysis {
        let reports = PoseFeatureSet.allCases.map { featureSet in
            report(featureSet, verdict: featureSet == best ? .go : .marginal, offset: featureSet == best ? 20 : 10)
        }
        return GateAnalysis(reports: reports, overall: .go, bestFeatureSet: best, thresholds: .default)
    }

    /// A small labeled trace for opening and copying tests.
    static func trace() -> PoseTrace {
        PoseTrace(
            cameraName: builtInCamera.name, layout: twoDisplays,
            segments: [
                TraceSegment(displayID: left.id, round: 1, samples: [sample(at: 0, yaw: -20)]),
                TraceSegment(displayID: right.id, round: 1, samples: [sample(at: 1, yaw: 20)]),
            ]
        )
    }

    // MARK: Calibration and the switch preview

    /// A Vision-angles profile for the two display layout: Left at -20 yaw, Right at +20.
    static func profile(
        layout: DisplayLayout = twoDisplays, createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    )
        -> CalibrationProfile
    {
        let profiles = layout.displays.enumerated().map { index, display in
            DisplayProfile(
                displayID: display.id, yaw: -20 + 40 * Double(index), pitch: 0, yawStd: 2, pitchStd: 1,
                sampleCount: 100)
        }
        return CalibrationProfile(
            features: .visionAngles, displays: profiles, yawScale: 2, pitchScale: 2.5,
            layoutFingerprint: layout.fingerprint, cameraName: builtInCamera.name, createdAt: createdAt)
    }

    /// A classification pointing at `best` (or elsewhere / no face).
    static func classification(
        _ kind: PoseClassification.Kind = .display, best: DisplayID? = left.id, margin: Double = 0.6
    ) -> PoseClassification {
        if kind == .noFace { return .noFace }
        let runnerUp = best == left.id ? right.id : left.id
        return PoseClassification(
            kind: kind, best: best, runnerUp: runnerUp, margin: kind == .display ? margin : 0, distances: [:])
    }

    /// A decision with sensible defaults: idle, looking at Left.
    static func decision(
        switchTo: DisplayID? = nil, phase: SwitchPhase = .idle, reason: SwitchHoldReason? = nil,
        classification: PoseClassification = Fixtures.classification()
    ) -> SwitchDecision {
        SwitchDecision(switchTo: switchTo, phase: phase, reason: reason, classification: classification)
    }

    // MARK: Focus

    static func window(
        _ id: UInt32 = 1, app: String = "Safari", title: String? = "Secret page", on display: DisplayInfo = left
    ) -> WindowSummary {
        WindowSummary(
            id: id, processID: Int32(id) + 100, appName: app, title: title, bounds: display.frame,
            displayID: display.id)
    }
}
