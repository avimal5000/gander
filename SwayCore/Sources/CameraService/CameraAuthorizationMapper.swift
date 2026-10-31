import AVFoundation
import SwayModels

/// Maps AVFoundation's authorization status onto Gander's `CameraAuthorization`.
enum CameraAuthorizationMapper {
    /// One-to-one mapping. A status added by a future SDK is treated as `.denied`, the safe choice because
    /// capture never starts unless the result is `.authorized`.
    static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
