import CameraService
import DisplayTracker
import PoseEstimator
import PoseTraces
import SwayModels
import SwayUI

/// Builds the concrete object graph. The only place that knows every module's concrete types.
@MainActor
enum AppComposition {
    static func makeModel() -> AppModel {
        let camera = CameraCaptureService()
        let poseSource = LivePoseSource(frameSource: camera, estimator: VisionPoseEstimator())
        return AppModel(
            camera: camera,
            poseSource: poseSource,
            displays: ScreenDisplayTracker(),
            traceStore: FileTraceStore(),
            analyzer: SeparabilityAnalyzer()
        )
    }
}
