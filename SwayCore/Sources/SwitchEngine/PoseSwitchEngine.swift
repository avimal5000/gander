import Foundation
import SwayModels

// SKELETON STUB (orchestrator). The SwitchEngine builder replaces this file. See CONTRACT.md.

/// Calibration fitting, pose classification, and the switch state machine.
public struct PoseSwitchEngine: SwitchEngineMaking {
    public init() {}

    public func fitProfile(
        from trace: PoseTrace,
        features: PoseFeatureSet,
        rounds: Set<Int>?
    ) throws -> CalibrationProfile {
        throw CalibrationError.tooFewDisplays
    }

    public func classify(
        _ pose: HeadPose?,
        with profile: CalibrationProfile,
        settings: SwitchSettings
    ) -> PoseClassification {
        .noFace
    }

    public func makeDecider(profile: CalibrationProfile, settings: SwitchSettings) -> any SwitchDeciding {
        StubDecider()
    }
}

private struct StubDecider: SwitchDeciding {
    mutating func process(_ sample: PoseSample, context: SwitchContext) -> SwitchDecision {
        SwitchDecision(switchTo: nil, phase: .idle, reason: .noFace, classification: .noFace)
    }

    mutating func reset() {}
}
