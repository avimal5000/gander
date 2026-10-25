import SwayModels

/// User-facing wording and menu bar symbols for camera state. Pure functions of model values.
extension CaptureStatus {
    /// True while frames are flowing.
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// The device in use, when running.
    var device: CameraDevice? {
        if case .running(let device) = self { return device }
        return nil
    }

    /// SF Symbol for the menu bar label (CONTRACT 6.5).
    func menuBarSymbol(hasFace: Bool) -> String {
        switch self {
        case .stopped: "eye.slash"
        case .starting: "eye"
        case .running: hasFace ? "eye.fill" : "eye.trianglebadge.exclamationmark"
        case .suspended: "pause.circle"
        case .interrupted, .failed: "exclamationmark.triangle"
        }
    }

    /// One-line state text, for example "Running" or "Suspended: screen locked".
    var summary: String {
        switch self {
        case .stopped: "Camera off"
        case .starting: "Starting camera\u{2026}"
        case .running: "Running"
        case .suspended(let reason): "Suspended: \(reason.userDescription)"
        case .interrupted(let message): "Interrupted: \(message)"
        case .failed(let error): "Failed: \(error.userMessage)"
        }
    }

    /// State text plus the camera name when known, for the menu status line.
    func statusLine(cameraName: String?) -> String {
        switch self {
        case .running:
            if let name = device?.name ?? cameraName { return "\(summary) \u{00B7} \(name)" }
            return summary
        default:
            return summary
        }
    }
}

extension SuspendReason {
    /// Lowercase phrase for the status line.
    var userDescription: String {
        switch self {
        case .systemSleep: "system asleep"
        case .displaysAsleep: "displays asleep"
        case .screenLocked: "screen locked"
        }
    }
}

extension CameraError {
    /// Plain-English description for the status line and banners.
    var userMessage: String {
        switch self {
        case .notAuthorized: "camera access was not granted"
        case .noDevice: "no camera was found"
        case .deviceUnavailable(let message): message
        case .configurationFailed(let message): message
        case .runtimeFailure(let message): message
        }
    }
}

extension TraceStoreError {
    /// Plain-English description for save and open failures.
    var userMessage: String {
        switch self {
        case .disabledInReleaseBuilds: "Traces are only saved in debug builds."
        case .io(let message): "File error: \(message)"
        case .decoding(let message): "This file is not a valid Sway trace: \(message)"
        }
    }
}

extension CalibrationError {
    /// Plain-English description for the report view when a calibration cannot be fitted.
    var userMessage: String {
        switch self {
        case .tooFewDisplays: "Not enough face samples on at least two displays to calibrate"
        case .featuresMissing(let features): "This trace has no \(features.title)"
        }
    }
}

/// Describes any thrown error for display.
func userMessage(for error: any Error) -> String {
    if let error = error as? TraceStoreError { return error.userMessage }
    if let error = error as? CalibrationError { return error.userMessage }
    if let error = error as? CameraError { return error.userMessage }
    return error.localizedDescription
}
