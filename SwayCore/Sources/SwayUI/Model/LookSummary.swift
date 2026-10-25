import SwayModels

/// What the popover's "Looking at" line says (SPEC F19): a small value that is assigned only when it changes, so the
/// always-alive popover does not redraw at the frame rate.
enum LookSummary: Equatable {
    /// The camera is off, or nothing classifies the look.
    case off
    case noFace
    case elsewhere
    /// The nearest calibrated display's label.
    case display(String)

    /// The popover line. One line in every case.
    var text: String {
        switch self {
        case .off: Formatting.missing
        case .noFace: "No face"
        case .elsewhere: "Looking elsewhere"
        case .display(let name): "Looking at \(name)"
        }
    }

    /// The summary of one classification; `label` names a display.
    init(_ classification: PoseClassification, label: (DisplayID) -> String) {
        switch classification.kind {
        case .noFace:
            self = .noFace
        case .elsewhere:
            self = .elsewhere
        case .display:
            self = classification.best.map { .display(label($0)) } ?? .noFace
        }
    }
}
