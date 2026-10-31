import GanderModels

/// Which rule picked a device.
enum CameraDeviceChoiceReason: Sendable, Equatable {
    /// The caller's preferred ID is connected.
    case preferred
    /// The first built-in camera.
    case builtIn
    /// `AVCaptureDevice.default(for: .video)`.
    case systemDefault
}

/// The outcome of device selection.
struct CameraDeviceChoice: Sendable, Equatable {
    var device: CameraDevice
    var reason: CameraDeviceChoiceReason
    /// True when a preferred ID was given but no connected device has it (the caller falls back silently).
    var preferredWasUnavailable: Bool
}

/// Pure device selection rule (CONTRACT 6.1), written over plain values so it is testable without hardware.
enum CameraDeviceSelector {
    /// Picks the device to capture from.
    ///
    /// Order: the preferred ID if it is connected, else the first built-in device, else the system default.
    /// The system default counts as connected even when discovery did not list it. An unknown preferred ID
    /// is not an error; it falls back and sets `preferredWasUnavailable`.
    ///
    /// - Parameters:
    ///   - preferredID: the caller's preferred `CameraDevice.id`, if any.
    ///   - devices: devices found by discovery, in discovery order.
    ///   - systemDefault: the system default video device, if any.
    /// - Throws: `CameraError.noDevice` when there is no device at all.
    static func select(
        preferredID: String?,
        devices: [CameraDevice],
        systemDefault: CameraDevice?
    ) throws -> CameraDeviceChoice {
        var connected = devices
        if let systemDefault, !devices.contains(where: { $0.id == systemDefault.id }) {
            connected.append(systemDefault)
        }

        if let preferredID, let match = connected.first(where: { $0.id == preferredID }) {
            return CameraDeviceChoice(device: match, reason: .preferred, preferredWasUnavailable: false)
        }
        let preferredWasUnavailable = preferredID != nil

        if let builtIn = connected.first(where: \.isBuiltIn) {
            return CameraDeviceChoice(
                device: builtIn, reason: .builtIn, preferredWasUnavailable: preferredWasUnavailable)
        }
        if let systemDefault {
            return CameraDeviceChoice(
                device: systemDefault, reason: .systemDefault, preferredWasUnavailable: preferredWasUnavailable)
        }
        throw CameraError.noDevice
    }
}
