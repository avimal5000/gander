#if DEBUG
import Foundation
import Observation
import SwayModels

/// Result of the last free recording.
enum RecordingResult: Equatable {
    case saved(URL)
    case failed(String)
}

/// Collects samples for a free (unlabeled) recording. DEBUG builds only (SPEC F6): release builds neither show
/// the control nor write traces.
@MainActor
@Observable
final class TraceRecorder {
    private(set) var isRecording = false
    private(set) var sampleCount = 0
    private(set) var lastResult: RecordingResult?
    @ObservationIgnored private var samples: [PoseSample] = []

    /// Seconds covered so far (first to last sample timestamp).
    var duration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.timestamp - first.timestamp)
    }

    func begin() {
        samples = []
        sampleCount = 0
        lastResult = nil
        isRecording = true
    }

    func append(_ sample: PoseSample) {
        guard isRecording else { return }
        samples.append(sample)
        sampleCount = samples.count
    }

    /// Stops recording and returns what was collected.
    func finish() -> [PoseSample] {
        isRecording = false
        let collected = samples
        samples = []
        return collected
    }

    func record(_ result: RecordingResult) {
        lastResult = result
    }
}

extension AppModel {
    /// Starts a free recording from the live samples.
    func startRecording() {
        guard streamTask != nil, !recorder.isRecording else { return }
        recorder.begin()
    }

    /// Stops the free recording and saves it as an unlabeled trace.
    func stopRecording() {
        guard recorder.isRecording else { return }
        let samples = recorder.finish()
        guard !samples.isEmpty else {
            recorder.record(.failed("No samples were recorded."))
            return
        }
        let trace = PoseTrace(
            createdAt: environment.now(),
            cameraName: currentCameraName,
            layout: layout,
            segments: [TraceSegment(displayID: nil, round: 0, samples: samples)]
        )
        do {
            recorder.record(.saved(try traceStore.save(trace)))
        } catch {
            log.error("Saving the recording failed: \(String(describing: error), privacy: .public)")
            recorder.record(.failed(userMessage(for: error)))
        }
    }

    /// Saves what was recorded when the camera stops under an active recording.
    func finishRecordingIfNeeded() {
        if recorder.isRecording { stopRecording() }
    }
}
#endif
