import GanderModels

/// What the Setup window's result step says (SPEC F20, CONTRACT 6.5.3): how well the new calibration separates the
/// displays, or why nothing was saved.
struct SetupResult: Equatable, Sendable {
    enum Quality: Equatable, Sendable {
        /// "Calibration looks good."
        case good
        /// Two displays are close together.
        case fair
        /// Two displays are hard to tell apart.
        case poor
        /// The fit failed and nothing was saved.
        case failed
    }

    var quality: Quality
    var text: String

    /// True when a calibration was saved.
    var isSaved: Bool { quality != .failed }

    static let good = "Calibration looks good."

    /// The fit failed: nothing was saved. `text` is the reason.
    static func failed(_ text: String) -> SetupResult {
        SetupResult(quality: .failed, text: text)
    }

    /// The fit left out the displays named in `names` (too few face samples while looking at them): nothing was saved.
    static func missingDisplays(_ names: [String]) -> SetupResult {
        .failed(
            "Gander couldn't see your face well enough while you looked at \(listed(names)). "
                + "Make sure the camera sees you from every display, then calibrate again.")
    }

    /// "A", "A and B", "A, B, and C".
    static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + (names.last ?? "")
        }
    }

    /// The verdict of the Vision-angles report in `analysis`, in words. With no report it reads as good without naming
    /// a pair.
    ///
    /// - Parameter name: the label of a display.
    init(analysis: GateAnalysis, name: (DisplayID) -> String) {
        let report = analysis.report(for: .visionAngles)
        let weakest = report?.pairs.min { $0.dPrime < $1.dPrime }
        let pair = weakest.map { (name($0.first), name($0.second)) }
        switch report?.verdict {
        case .marginal?:
            quality = .fair
            if let (first, second) = pair {
                text =
                    "Calibration saved. \(first) and \(second) are close together, "
                    + "so switching between them may be slower."
            } else {
                text = "Calibration saved. Some displays are close together, so switching between them may be slower."
            }
        case .noGo?:
            quality = .poor
            if let (first, second) = pair {
                text =
                    "Calibration saved, but \(first) and \(second) are hard to tell apart. "
                    + "Try moving the camera, then calibrate again."
            } else {
                text =
                    "Calibration saved, but some displays are hard to tell apart. "
                    + "Try moving the camera, then calibrate again."
            }
        case .insufficientData?:
            // Setup saves only a calibration that covers every display, so this means few samples somewhere.
            quality = .fair
            text =
                "Calibration saved, but Gander saw your face only briefly on some displays. "
                + "If switching feels unreliable, calibrate again."
        case .go?, nil:
            quality = .good
            text = Self.good
        }
    }

    private init(quality: Quality, text: String) {
        self.quality = quality
        self.text = text
    }
}
