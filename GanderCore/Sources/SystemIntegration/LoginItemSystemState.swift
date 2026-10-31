import ServiceManagement

/// A mirror of `SMAppService.Status`, so the mapping to `LoginItemStatus` is a pure function that tests can feed
/// every case, including the unknown one that the real enum can't be made to produce.
enum LoginItemSystemState: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    /// A value the system added after this code was written.
    case unknown

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}
