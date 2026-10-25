#if DEBUG
import CoreGraphics
import Foundation
import SwayModels

/// Fake dependencies and sample data for SwiftUI previews. Compiled in DEBUG builds only; the unit tests have
/// their own, more controllable fakes.
enum PreviewSupport {
    static let leftDisplay = DisplayInfo(
        id: "preview-left", cgDisplayID: 1, name: "Left monitor",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isBuiltIn: false, isMain: true
    )
    static let rightDisplay = DisplayInfo(
        id: "preview-right", cgDisplayID: 2, name: "Right monitor",
        frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isBuiltIn: false, isMain: false
    )
    static let layout = DisplayLayout(displays: [leftDisplay, rightDisplay])
    static let camera = CameraDevice(id: "preview-camera", name: "FaceTime HD Camera", isBuiltIn: true)

    /// A pose looking at `display` (index 0 or 1) with a little deterministic wobble.
    static func pose(display: Int, step: Int) -> HeadPose {
        let wobble = sin(Double(step) * 0.7)
        let yaw = (display == 0 ? -18.0 : 18.0) + 2.5 * wobble
        let pitch = -3.0 + 1.5 * cos(Double(step) * 0.9)
        return HeadPose(
            yaw: yaw, pitch: pitch, roll: 1.2 * wobble, faceConfidence: 0.96,
            faceBounds: CGRect(x: 0.32, y: 0.28, width: 0.34, height: 0.44),
            landmarkYaw: 0.9 * yaw, landmarkPitch: 0.9 * pitch
        )
    }

    /// A finished two-round gate trace with two well-separated clusters.
    static func trace() -> PoseTrace {
        var segments: [TraceSegment] = []
        for round in 1...2 {
            for (index, display) in [leftDisplay, rightDisplay].enumerated() {
                let samples = (0..<60).map { step in
                    PoseSample(timestamp: Double(step) / 15, pose: pose(display: index, step: step + round))
                }
                segments.append(TraceSegment(displayID: display.id, round: round, samples: samples))
            }
        }
        return PoseTrace(cameraName: camera.name, layout: layout, segments: segments)
    }

    /// A hand-built GO analysis matching `trace()`.
    static func analysis() -> GateAnalysis {
        func report(_ featureSet: PoseFeatureSet, scale: Double) -> SeparabilityReport {
            let left = DisplayPoseStats(
                displayID: leftDisplay.id, displayName: leftDisplay.name, frameCount: 120, faceCount: 118,
                meanX: -18 * scale, meanY: -3 * scale, stdX: 1.8, stdY: 1.1
            )
            let right = DisplayPoseStats(
                displayID: rightDisplay.id, displayName: rightDisplay.name, frameCount: 120, faceCount: 116,
                meanX: 18 * scale, meanY: -3 * scale, stdX: 1.9, stdY: 1.0
            )
            return SeparabilityReport(
                featureSet: featureSet, displays: [left, right],
                pairs: [
                    PairSeparation(
                        first: leftDisplay.id, second: rightDisplay.id, meanDistance: 36 * scale, dPrime: 17.5)
                ],
                accuracy: 1, verdict: .go,
                notes: ["The weakest pair is Left monitor / Right monitor with d\u{2032} 17.5."]
            )
        }
        return GateAnalysis(
            reports: [report(.visionAngles, scale: 1), report(.landmarkAngles, scale: 0.9)],
            overall: .go, bestFeatureSet: .visionAngles, thresholds: .default
        )
    }

    /// A calibration profile matching `trace()`: the two preview displays, well separated in yaw.
    static func profile() -> CalibrationProfile {
        CalibrationProfile(
            features: .visionAngles,
            displays: [
                DisplayProfile(
                    displayID: leftDisplay.id, yaw: -18, pitch: -3, yawStd: 1.8, pitchStd: 1.1, sampleCount: 120),
                DisplayProfile(
                    displayID: rightDisplay.id, yaw: 18, pitch: -3, yawStd: 1.9, pitchStd: 1.0, sampleCount: 120),
            ],
            yawScale: 1.9, pitchScale: 2.5, layoutFingerprint: layout.fingerprint, cameraName: camera.name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// A model wired to fakes.
    ///
    /// - Parameters:
    ///   - live: simulates a running camera with a face.
    ///   - withAnalysis: adopts a report.
    ///   - withProfile: adopts a calibration profile for the Switch preview.
    ///   - focusTrusted: opens the Focus Test window's state with Accessibility granted (`true`) or not (`false`);
    ///     `nil` leaves the window closed.
    @MainActor
    static func model(
        live: Bool = false, withAnalysis: Bool = false, showReport: Bool = false, withProfile: Bool = false,
        focusTrusted: Bool? = nil
    ) -> AppModel {
        // Previews share one defaults suite; start each from a blank slate so a stored profile never leaks in.
        let defaults = UserDefaults(suiteName: "sway.preview") ?? .standard
        defaults.removeObject(forKey: DefaultsKey.calibrationProfile)
        let model = AppModel(
            camera: PreviewFrameSource(),
            poseSource: PreviewPoseSource(),
            displays: PreviewDisplays(),
            traceStore: PreviewTraceStore(),
            analyzer: PreviewAnalyzer(),
            engine: PreviewEngine(),
            focus: PreviewFocus(trusted: focusTrusted ?? false),
            defaults: defaults,
            environment: AppModelEnvironment(
                clock: { 0 }, now: { Date() }, system: PreviewSystem(), overlay: PreviewOverlay(),
                notificationCenter: NotificationCenter(), gateTickInterval: nil, focusTickInterval: nil,
                cameraStartTimeout: 10
            )
        )
        if withAnalysis {
            model.adopt(analysis(), trace: trace(), source: .gateTest)
            model.isShowingReport = showReport
        }
        if withProfile {
            model.refitCalibration(from: trace())
        }
        if live {
            model.liveEnabled = true
            model.rebuildDecider()
            model.handle(.status(.running(camera)))
            for step in 0..<150 {
                model.handle(.sample(PoseSample(timestamp: Double(step) / 15, pose: pose(display: 1, step: step))))
            }
        }
        if focusTrusted != nil {
            model.noteWindowRequested(SwayWindowID.focusTest)
        }
        return model
    }
}

private final class PreviewFrameSource: FrameSource {
    func authorizationStatus() -> CameraAuthorization { .authorized }
    func requestAuthorization() async -> CameraAuthorization { .authorized }
    func availableDevices() -> [CameraDevice] {
        [
            PreviewSupport.camera,
            CameraDevice(id: "preview-external", name: "Logitech C922", isBuiltIn: false),
        ]
    }
    func start(
        deviceID: String?, frameRate: Double, frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {}
    func stop() async {}
}

private final class PreviewPoseSource: PoseSource {
    func start(_ configuration: PoseSourceConfiguration) async throws -> AsyncStream<PoseSourceEvent> {
        AsyncStream { _ in }
    }
    func stop() async {}
}

@MainActor
private final class PreviewDisplays: DisplayProviding {
    var currentLayout: DisplayLayout { PreviewSupport.layout }
    func layouts() -> AsyncStream<DisplayLayout> { AsyncStream { _ in } }
}

private struct PreviewTraceStore: TraceStoring {
    var directory: URL { FileManager.default.temporaryDirectory }
    func save(_ trace: PoseTrace) throws -> URL { directory.appendingPathComponent("preview.json") }
    func load(_ url: URL) throws -> PoseTrace { throw TraceStoreError.io("Previews cannot load traces.") }
    func list() throws -> [URL] { [] }
}

private struct PreviewAnalyzer: SeparabilityAnalyzing {
    func analyze(_ trace: PoseTrace, thresholds: GateThresholds) -> GateAnalysis { PreviewSupport.analysis() }

    func classify(_ pose: HeadPose, using report: SeparabilityReport) -> DisplayClassification? {
        guard let point = report.featureSet.point(of: pose) else { return nil }
        let scored = report.displays.map { stats -> (DisplayID, Double) in
            let zx = (point.x - stats.meanX) / max(stats.stdX, 0.5)
            let zy = (point.y - stats.meanY) / max(stats.stdY, 0.5)
            return (stats.displayID, (zx * zx + zy * zy).squareRoot())
        }
        .sorted { $0.1 < $1.1 }
        guard let best = scored.first else { return nil }
        return DisplayClassification(
            displayID: best.0, distance: best.1, runnerUpDistance: scored.dropFirst().first?.1
        )
    }

    func markdownSummary(of analysis: GateAnalysis, trace: PoseTrace) -> String { "## Preview" }
}

@MainActor
private final class PreviewSystem: SystemInteracting {
    func openCameraPrivacySettings() {}
    func openAccessibilityPrivacySettings() {}
    func revealInFinder(_ url: URL) {}
    func copyToPasteboard(_ string: String) {}
    func chooseTraceFile(startingIn directory: URL) -> URL? { nil }
    func terminateApp() {}
}

@MainActor
private final class PreviewOverlay: GateOverlayPresenting {
    var onCancelRequested: (@MainActor () -> Void)?
    func canPresent(on display: DisplayInfo) -> Bool { true }
    func present(_ progress: GateProgress) {}
    func dismiss() {}
}

/// Fits the canned preview profile and classifies by nearest preview display; its decider never switches.
private struct PreviewEngine: SwitchEngineMaking {
    func fitProfile(from trace: PoseTrace, features: PoseFeatureSet, rounds: Set<Int>?) throws -> CalibrationProfile {
        PreviewSupport.profile()
    }

    func classify(_ pose: HeadPose?, with profile: CalibrationProfile, settings: SwitchSettings) -> PoseClassification {
        guard let pose else { return .noFace }
        let distances = Dictionary(
            uniqueKeysWithValues: profile.displays.map { display in
                let dx = (pose.yaw - display.yaw) / profile.yawScale
                let dy = (pose.pitch - display.pitch) / profile.pitchScale
                return (display.displayID, (dx * dx + dy * dy).squareRoot())
            })
        let ranked = distances.sorted { $0.value < $1.value }
        guard let best = ranked.first, let second = ranked.dropFirst().first else { return .noFace }
        let sum = best.value + second.value
        return PoseClassification(
            kind: .display, best: best.key, runnerUp: second.key,
            margin: sum == 0 ? 0 : (second.value - best.value) / sum, distances: distances)
    }

    func makeDecider(profile: CalibrationProfile, settings: SwitchSettings) -> any SwitchDeciding {
        PreviewDecider(engine: self, profile: profile)
    }
}

private struct PreviewDecider: SwitchDeciding {
    let engine: PreviewEngine
    let profile: CalibrationProfile

    mutating func process(_ sample: PoseSample, context: SwitchContext) -> SwitchDecision {
        SwitchDecision(
            switchTo: nil, phase: context.isFocusLocked ? .locked : .idle, reason: nil,
            classification: engine.classify(sample.pose, with: profile, settings: .default))
    }

    mutating func reset() {}
}

private struct PreviewFocus: FocusControlling {
    let trusted: Bool

    func isTrusted() -> Bool { trusted }
    func requestTrust() {}

    func lastUsedWindows(in layout: DisplayLayout) async -> [DisplayID: WindowSummary] {
        guard let first = layout.displays.first else { return [:] }
        return [
            first.id: WindowSummary(
                id: 1, processID: 100, appName: "Safari", title: "Sway", bounds: first.frame, displayID: first.id)
        ]
    }

    func focusedDisplay(in layout: DisplayLayout) async -> DisplayID? { layout.displays.first?.id }

    func focus(display: DisplayID, in layout: DisplayLayout) async -> FocusResult { .noWindow(display) }
}
#endif
