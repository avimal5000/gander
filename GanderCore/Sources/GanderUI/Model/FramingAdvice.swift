import CoreGraphics
import GanderModels

/// The live hint on the Setup window's camera check (SPEC F20): whether the camera sees the face well enough to
/// calibrate. A pure function of the latest pose.
enum FramingAdvice: Equatable, Sendable {
    case noFace
    case closer
    case back
    case center
    case good

    /// A face box shorter than this (fraction of the frame height) is too far away.
    static let minimumFaceHeight: CGFloat = 0.18
    /// A face box taller than this is too close.
    static let maximumFaceHeight: CGFloat = 0.6
    /// The face center must stay inside this range on both axes (fraction of the frame).
    static let centerRange: ClosedRange<CGFloat> = 0.2...0.8

    /// The advice for `pose`; the first rule that applies wins, in the order the cases are listed.
    init(_ pose: HeadPose?) {
        guard let bounds = pose?.faceBounds else {
            self = .noFace
            return
        }
        if bounds.height < Self.minimumFaceHeight {
            self = .closer
        } else if bounds.height > Self.maximumFaceHeight {
            self = .back
        } else if !Self.centerRange.contains(bounds.midX) || !Self.centerRange.contains(bounds.midY) {
            self = .center
        } else {
            self = .good
        }
    }

    var text: String {
        switch self {
        case .noFace: "Gander can't see your face yet."
        case .closer: "Move a little closer to the camera."
        case .back: "Move back a little."
        case .center: "Center your face in the camera's view."
        case .good: "Looks good."
        }
    }
}
