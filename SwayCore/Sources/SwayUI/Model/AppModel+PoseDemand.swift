import Foundation
import SwayModels

// How much frame rate the pose source is asked for (SPEC D45, CONTRACT 6.5.5 item 2). The source throttles itself
// (`LivePoseSource` with its `AdaptiveFrameRate`); the model only says what the app needs, and only when that changes.
extension AppModel {
    // MARK: Wanted demand

    /// What the camera is running for right now.
    ///
    /// - `.full` for everything but plain tracking: the gate test, a calibration, Setup's camera check, the Pose Debug
    ///   window (its numbers and plot are live), and the Focus Test window.
    /// - `.reduced` while nothing is switched on the poses: Focus Lock is on, or Accessibility is missing.
    /// - `.adaptive` otherwise: full rate while a face is there, a lower rate once none has been seen for a while.
    var wantedPoseDemand: PoseDemand {
        if gateRunState != .idle || isSetupUsingCamera || poseDebugVisible || focusTestVisible { return .full }
        if focusLocked || trackingStatus == .needsAccessibility { return .reduced }
        return .adaptive
    }

    // MARK: Applying it

    /// Hands the wanted demand to the pose source when it differs from the one it has. Cheap; call it whenever one of
    /// the inputs may have changed. Does nothing while no stream runs: a start resets the source to `.full`, so
    /// ``startPoseSource()`` applies the demand once after each start.
    /// - Parameter force: apply even when the demand is unchanged (right after a start).
    func syncPoseDemand(force: Bool = false) {
        guard streamTask != nil else {
            appliedPoseDemand = nil
            return
        }
        let demand = wantedPoseDemand
        guard force || demand != appliedPoseDemand else { return }
        appliedPoseDemand = demand
        poseSource.setDemand(demand)
    }

    // MARK: Pose Debug window

    /// The Pose Debug window appeared, disappeared, minimized, or came back: it needs the full frame rate exactly while
    /// it shows live content. Ignored for the copy SwiftUI opens at launch, which the launch guard closes unseen
    /// (nobody asked for it).
    func setPoseDebugVisible(_ visible: Bool) {
        let value = visible && hasWindowRequest(SwayWindowID.poseDebug)
        guard value != poseDebugVisible else { return }
        poseDebugVisible = value
        syncPoseDemand()
    }
}
