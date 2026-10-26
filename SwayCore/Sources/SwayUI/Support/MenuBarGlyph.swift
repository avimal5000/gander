/// The four states of the menu bar icon (SPEC F25, D37): the Swing mark with small changes.
enum MenuBarGlyph: CaseIterable, Hashable, Sendable {
    /// Solid mark: Tracking, No face, Calibrating, Starting.
    case tracking
    /// Dimmed mark with a hollow end point: Paused, One display, Suspended.
    case paused
    /// Mark with a lock badge: Focus Lock.
    case focusLock
    /// Mark with a dot: the statuses that need the user.
    case attention

    /// The glyph for a tracking status, exactly as SPEC F25's table says.
    init(_ status: TrackingStatus) {
        switch status {
        case .tracking, .noFace, .calibrating, .starting:
            self = .tracking
        case .paused, .oneDisplay, .suspended:
            self = .paused
        case .focusLock:
            self = .focusLock
        case .cameraBlocked, .cameraFailed, .cameraBusy, .cameraDisconnected, .needsCalibration,
            .needsAccessibility:
            self = .attention
        }
    }

    /// How the mark is drawn for a glyph.
    struct Style: Equatable, Sendable {
        /// 1 for a solid mark; less for a dimmed one.
        var opacity: Double
        /// The end point is a ring instead of a disc.
        var hollowEnd: Bool
        /// A lock at the bottom right.
        var lockBadge: Bool
        /// A dot at the top right.
        var alertDot: Bool
    }

    var style: Style {
        switch self {
        case .tracking: Style(opacity: 1, hollowEnd: false, lockBadge: false, alertDot: false)
        case .paused: Style(opacity: 0.5, hollowEnd: true, lockBadge: false, alertDot: false)
        case .focusLock: Style(opacity: 1, hollowEnd: false, lockBadge: true, alertDot: false)
        case .attention: Style(opacity: 1, hollowEnd: false, lockBadge: false, alertDot: true)
        }
    }
}
