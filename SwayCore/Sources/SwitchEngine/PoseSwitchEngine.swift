import SwayModels

/// Calibration fitting, pose classification, and the switch state machine (SPEC M2, CONTRACT section 6.6).
///
/// A stateless facade over three internal pieces: `ProfileFitter`, `PoseClassifier`, and
/// `SwitchStateMachine`. Safe to share and to call from any thread.
public struct PoseSwitchEngine: SwitchEngineMaking {
    public init() {}

    public func fitProfile(
        from trace: PoseTrace,
        features: PoseFeatureSet,
        rounds: Set<Int>?
    ) throws -> CalibrationProfile {
        try ProfileFitter().fit(from: trace, features: features, rounds: rounds)
    }

    public func classify(
        _ pose: HeadPose?,
        with profile: CalibrationProfile,
        settings: SwitchSettings
    ) -> PoseClassification {
        PoseClassifier(profile: profile, settings: settings).classify(pose)
    }

    public func makeDecider(profile: CalibrationProfile, settings: SwitchSettings) -> any SwitchDeciding {
        SwitchStateMachine(profile: profile, settings: settings)
    }
}
