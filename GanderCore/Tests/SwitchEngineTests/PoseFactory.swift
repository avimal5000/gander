import CoreGraphics
import Foundation
import GanderModels

/// Builds a pose with the given angles. Vision angles are the default feature set; landmark angles are `nil`
/// unless given.
func makePose(
    yaw: Double,
    pitch: Double,
    confidence: Double = 0.95,
    landmarkYaw: Double? = nil,
    landmarkPitch: Double? = nil
) -> HeadPose {
    HeadPose(
        yaw: yaw,
        pitch: pitch,
        roll: 0,
        faceConfidence: confidence,
        faceBounds: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3),
        landmarkYaw: landmarkYaw,
        landmarkPitch: landmarkPitch
    )
}

/// A sample at time `t`; `yaw == nil` means no face.
func makeSample(_ t: Double, yaw: Double?, pitch: Double = 8, confidence: Double = 0.95) -> PoseSample {
    PoseSample(timestamp: t, pose: yaw.map { makePose(yaw: $0, pitch: pitch, confidence: confidence) })
}

/// Left-to-right layout of 1920x1080 displays named "Display <n>".
func makeLayout(_ ids: [DisplayID]) -> DisplayLayout {
    DisplayLayout(
        displays: ids.enumerated().map { index, id in
            DisplayInfo(
                id: id,
                cgDisplayID: UInt32(index + 1),
                name: "Display \(index + 1)",
                frame: CGRect(x: Double(index) * 1920, y: 0, width: 1920, height: 1080),
                isBuiltIn: index == 0,
                isMain: index == 0
            )
        }
    )
}
