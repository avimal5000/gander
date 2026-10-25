import Foundation

/// One display's calibrated head pose: where the head points while looking at that display.
public struct DisplayProfile: Sendable, Equatable, Codable {
    public let displayID: DisplayID
    /// Mean of the display's face samples, degrees, in the profile's feature set.
    public let yaw: Double
    public let pitch: Double
    /// Sample standard deviations (n - 1), degrees, unfloored. Informational; distances use the profile's scales.
    public let yawStd: Double
    public let pitchStd: Double
    /// Face samples the means came from.
    public let sampleCount: Int

    public init(displayID: DisplayID, yaw: Double, pitch: Double, yawStd: Double, pitchStd: Double, sampleCount: Int) {
        self.displayID = displayID
        self.yaw = yaw
        self.pitch = pitch
        self.yawStd = yawStd
        self.pitchStd = pitchStd
        self.sampleCount = sampleCount
    }
}

/// Per-display pose profiles fitted from a labeled trace (the gate test today, guided calibration in M5).
///
/// Plain data, so it can be stored and shown anywhere; `SwitchEngine` fits it and classifies against it.
public struct CalibrationProfile: Sendable, Equatable, Codable {
    /// Bump when stored fields change meaning; a profile with another version is refitted, not reused.
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    /// Which pose features the profile uses. Live tracking uses `.visionAngles`.
    public let features: PoseFeatureSet
    /// Profiles of the displays that had enough face samples, in the trace layout's left-to-right order.
    public let displays: [DisplayProfile]
    /// Axis scales, degrees, that normalize distances: the pooled within-display standard deviation of each axis,
    /// floored. Always `pitchScale >= yawScale`, so pitch never weighs more than yaw.
    public let yawScale: Double
    public let pitchScale: Double
    /// `DisplayLayout.fingerprint` of the layout the trace was recorded on. A different current fingerprint
    /// means the profile is stale (displays moved, added, or removed).
    public let layoutFingerprint: String
    /// Camera the trace was recorded with; poses from another camera do not match the profile.
    public let cameraName: String?
    public let createdAt: Date

    public init(
        formatVersion: Int = CalibrationProfile.currentFormatVersion,
        features: PoseFeatureSet,
        displays: [DisplayProfile],
        yawScale: Double,
        pitchScale: Double,
        layoutFingerprint: String,
        cameraName: String?,
        createdAt: Date
    ) {
        self.formatVersion = formatVersion
        self.features = features
        self.displays = displays
        self.yawScale = yawScale
        self.pitchScale = pitchScale
        self.layoutFingerprint = layoutFingerprint
        self.cameraName = cameraName
        self.createdAt = createdAt
    }

    public func profile(for id: DisplayID) -> DisplayProfile? {
        displays.first { $0.displayID == id }
    }

    /// True when the profile was fitted on this exact display arrangement and is in the current format.
    public func matches(_ layout: DisplayLayout) -> Bool {
        formatVersion == Self.currentFormatVersion && layoutFingerprint == layout.fingerprint
    }
}

/// Why a profile could not be fitted.
public enum CalibrationError: Error, Sendable, Equatable {
    /// Fewer than two displays have enough face samples to profile.
    case tooFewDisplays
    /// No sample in the trace has the requested features (for example landmarks in a live recording).
    case featuresMissing(PoseFeatureSet)
}

/// Where one pose points, relative to a calibration profile.
public struct PoseClassification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// No usable face: no pose, confidence below the minimum, or the profile's features are missing.
        case noFace
        /// Outside the region around the calibrated displays (keyboard, phone, looking away).
        case elsewhere
        /// Nearest `best`.
        case display
    }

    public let kind: Kind
    /// Nearest calibrated display; `nil` only for `.noFace`.
    public let best: DisplayID?
    /// Second nearest; `nil` for `.noFace`.
    public let runnerUp: DisplayID?
    /// `(dRunnerUp - dBest) / (dRunnerUp + dBest)`: 0 on the boundary between the two, 1 at `best`'s center.
    /// 0 unless `kind == .display`.
    public let margin: Double
    /// Normalized distance (axis-scale units) to every calibrated display; empty for `.noFace`.
    public let distances: [DisplayID: Double]

    public init(kind: Kind, best: DisplayID?, runnerUp: DisplayID?, margin: Double, distances: [DisplayID: Double]) {
        self.kind = kind
        self.best = best
        self.runnerUp = runnerUp
        self.margin = margin
        self.distances = distances
    }

    public static let noFace = PoseClassification(kind: .noFace, best: nil, runnerUp: nil, margin: 0, distances: [:])
}

/// Tunables for the switch decision (PLAN.md section 3, key rule). M5 exposes some of them as settings.
public struct SwitchSettings: Sendable, Equatable, Codable {
    /// Seconds a new display must be held before focus switches.
    public var dwell: Double
    /// Margin a pose needs to start dwelling on a display.
    public var enterMargin: Double
    /// Lower margin that keeps an ongoing dwell alive (hysteresis band).
    public var stayMargin: Double
    /// Longest run of no-face, elsewhere, or uncertain samples, in seconds, that a dwell survives.
    public var maxGap: Double
    /// Seconds after a switch during which no new dwell starts.
    public var cooldown: Double
    /// Faces below this Vision confidence count as no face.
    public var minFaceConfidence: Double
    /// Degrees beyond the outermost calibrated yaw (either side) after which a pose is elsewhere.
    public var elsewhereYawMargin: Double
    /// Degrees beyond the outermost calibrated pitch (either side) after which a pose is elsewhere.
    public var elsewherePitchMargin: Double

    public init(
        dwell: Double,
        enterMargin: Double,
        stayMargin: Double,
        maxGap: Double,
        cooldown: Double,
        minFaceConfidence: Double,
        elsewhereYawMargin: Double,
        elsewherePitchMargin: Double
    ) {
        self.dwell = dwell
        self.enterMargin = enterMargin
        self.stayMargin = stayMargin
        self.maxGap = maxGap
        self.cooldown = cooldown
        self.minFaceConfidence = minFaceConfidence
        self.elsewhereYawMargin = elsewhereYawMargin
        self.elsewherePitchMargin = elsewherePitchMargin
    }

    public static let `default` = SwitchSettings(
        dwell: 0.40,
        enterMargin: 0.30,
        stayMargin: 0.15,
        maxGap: 0.25,
        cooldown: 0.75,
        minFaceConfidence: 0.5,
        elsewhereYawMargin: 20,
        elsewherePitchMargin: 15
    )
}

/// Facts from outside the pose stream that the decider needs, passed with every sample.
public struct SwitchContext: Sendable, Equatable {
    /// Display whose window has keyboard focus now; `nil` if unknown (any display may then be switched to).
    public var focusedDisplay: DisplayID?
    /// Focus Lock or pause is on: never switch.
    public var isFocusLocked: Bool
    /// Displays focus may move to; `nil` means every calibrated display. A pose nearest a display outside this
    /// set never starts a dwell (`SwayPolicy.maxTrackedDisplays` is applied here by the caller).
    public var targets: Set<DisplayID>?

    public init(focusedDisplay: DisplayID?, isFocusLocked: Bool = false, targets: Set<DisplayID>? = nil) {
        self.focusedDisplay = focusedDisplay
        self.isFocusLocked = isFocusLocked
        self.targets = targets
    }
}

/// The decider's state after a sample.
public enum SwitchPhase: Sendable, Equatable {
    case idle
    /// Holding on `display`; `progress` is the elapsed fraction of the dwell, 0...1.
    case dwelling(display: DisplayID, progress: Double)
    /// A switch fired; no new dwell starts before the sample timestamp `until`.
    case coolingDown(until: Double)
    /// Focus Lock is on.
    case locked
}

/// Why a sample did not fire a switch.
public enum SwitchHoldReason: Sendable, Equatable {
    case noFace
    case elsewhere
    /// Nearest display's margin is below the threshold that applies.
    case uncertain
    /// The pose points at the display that already has focus.
    case alreadyFocused
    /// Nearest display is outside `SwitchContext.targets`.
    case notATarget
    /// Dwell in progress, not yet complete.
    case dwelling
    case coolingDown
    case focusLocked
}

/// The decider's output for one sample.
public struct SwitchDecision: Sendable, Equatable {
    /// Set exactly on the sample that completes a dwell: move focus to this display now.
    public let switchTo: DisplayID?
    public let phase: SwitchPhase
    /// Why nothing fired; `nil` when `switchTo` is set.
    public let reason: SwitchHoldReason?
    public let classification: PoseClassification

    public init(switchTo: DisplayID?, phase: SwitchPhase, reason: SwitchHoldReason?, classification: PoseClassification)
    {
        self.switchTo = switchTo
        self.phase = phase
        self.reason = reason
        self.classification = classification
    }
}

/// A stateful switch decider bound to one profile and settings. Pure: no clock, no I/O; time comes only from
/// sample timestamps, so recorded traces replay deterministically.
public protocol SwitchDeciding: Sendable {
    /// Classifies the sample and advances the state machine.
    mutating func process(_ sample: PoseSample, context: SwitchContext) -> SwitchDecision
    /// Drops any dwell or cooldown, as after a restart or a layout change.
    mutating func reset()
}

/// Fits calibration profiles, classifies poses, and creates deciders. Implemented by
/// `SwitchEngine.PoseSwitchEngine`.
public protocol SwitchEngineMaking: Sendable {
    /// Fits a profile from a labeled trace's segments, using face samples with the given features.
    /// - Parameter rounds: only segments from these rounds; `nil` uses every round.
    /// - Throws: `CalibrationError`.
    func fitProfile(from trace: PoseTrace, features: PoseFeatureSet, rounds: Set<Int>?) throws -> CalibrationProfile
    /// Classifies one pose (`nil` means no face) against a profile.
    func classify(_ pose: HeadPose?, with profile: CalibrationProfile, settings: SwitchSettings) -> PoseClassification
    /// A fresh decider in the idle phase.
    func makeDecider(profile: CalibrationProfile, settings: SwitchSettings) -> any SwitchDeciding
}
