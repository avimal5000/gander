import Foundation

/// Identifies a saved calibration: the displays it profiles and the camera it was recorded with.
public struct CalibrationKey: Hashable, Sendable, Codable {
    /// The profiled displays, sorted by raw value.
    public let displayIDs: [DisplayID]
    public let cameraName: String?

    public init(displayIDs: some Collection<DisplayID>, cameraName: String?) {
        self.displayIDs = displayIDs.sorted { $0.rawValue < $1.rawValue }
        self.cameraName = cameraName
    }
}

extension CalibrationProfile {
    /// The library key: this profile's display set and camera.
    public var key: CalibrationKey { CalibrationKey(displayIDs: displays.map(\.displayID), cameraName: cameraName) }

    /// The displays this profile covers.
    public var displayIDs: Set<DisplayID> { Set(displays.map(\.displayID)) }

    /// The same profile with only the displays in `ids`, in the saved order. Scales and metadata are kept, so poses
    /// classify exactly as before among the remaining displays.
    public func restricted(to ids: Set<DisplayID>) -> CalibrationProfile {
        CalibrationProfile(
            formatVersion: formatVersion,
            features: features,
            displays: displays.filter { ids.contains($0.displayID) },
            yawScale: yawScale,
            pitchScale: pitchScale,
            layoutFingerprint: layoutFingerprint,
            cameraName: cameraName,
            createdAt: createdAt
        )
    }
}

/// The calibration chosen for the current displays and camera.
public struct CalibrationMatch: Sendable, Equatable {
    /// What to classify against: the saved profile restricted to the connected displays.
    public let profile: CalibrationProfile
    /// The profile as saved; its `key` identifies it in the library.
    public let saved: CalibrationProfile

    public init(profile: CalibrationProfile, saved: CalibrationProfile) {
        self.profile = profile
        self.saved = saved
    }

    /// True when the saved profile covers displays that are not connected now (for example the laptop lid is closed).
    public var isPartial: Bool { saved.displays.count > profile.displays.count }
}

/// Every saved calibration, at most one per display set and camera (SPEC D24).
///
/// A calibration belongs to the set of displays it profiles, not to their exact arrangement: changing a resolution or
/// moving a display in System Settings keeps it. It also covers any two or more of its displays, so unplugging one
/// keeps tracking going on the rest. A display set that no saved profile covers is unknown, and tracking waits for a
/// calibration.
public struct CalibrationLibrary: Sendable, Equatable, Codable {
    /// Bump when the stored shape changes meaning.
    public static let currentFormatVersion = 1
    /// Most profiles kept; saving another drops the least recently saved.
    public static let maxProfiles = 24

    public let formatVersion: Int
    /// Newest first.
    public private(set) var profiles: [CalibrationProfile]

    public init(profiles: [CalibrationProfile] = []) {
        self.formatVersion = Self.currentFormatVersion
        self.profiles = []
        for profile in profiles.reversed() { save(profile) }
    }

    /// Saves `profile` as the newest, replacing a saved profile with the same key. Profiles with fewer than two
    /// displays another format version, or non-finite or non-positive scales are ignored: they can never be used.
    public mutating func save(_ profile: CalibrationProfile) {
        guard profile.displays.count >= 2, profile.formatVersion == CalibrationProfile.currentFormatVersion,
            profile.isUsable
        else {
            return
        }
        profiles.removeAll { $0.key == profile.key }
        profiles.insert(profile, at: 0)
        if profiles.count > Self.maxProfiles { profiles.removeLast(profiles.count - Self.maxProfiles) }
    }

    /// Removes the profile saved under `key`, if any.
    public mutating func remove(_ key: CalibrationKey) {
        profiles.removeAll { $0.key == key }
    }

    /// The calibration to track with on `layout` using the camera named `cameraName`; `nil` if none fits.
    ///
    /// Candidates are profiles for the same camera (`nil` matches only `nil`) whose displays include every display in
    /// `layout`, which needs at least two. The candidate with the fewest extra displays wins, so an exact display set
    /// comes first; ties go to the most recently saved.
    public func resolve(for layout: DisplayLayout, cameraName: String?) -> CalibrationMatch? {
        let connected = Set(layout.displays.map(\.id))
        guard connected.count >= 2 else { return nil }
        let best = profiles.enumerated()
            .filter { $0.element.cameraName == cameraName && connected.isSubset(of: $0.element.displayIDs) }
            .min { ($0.element.displays.count, $0.offset) < ($1.element.displays.count, $1.offset) }?
            .element
        return best.map { CalibrationMatch(profile: $0.restricted(to: connected), saved: $0) }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case formatVersion, profiles
    }

    /// Decodes leniently: a profile that fails to decode, or has another format version, is dropped instead of
    /// failing the whole library. A library of another format version decodes as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        self.formatVersion = Self.currentFormatVersion
        self.profiles = []
        guard version == Self.currentFormatVersion else { return }
        let stored = try container.decode([LossyProfile].self, forKey: .profiles).compactMap(\.profile)
        for profile in stored.reversed() { save(profile) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(profiles, forKey: .profiles)
    }

    /// One stored profile, or `nil` when it does not decode.
    private struct LossyProfile: Decodable {
        let profile: CalibrationProfile?

        init(from decoder: any Decoder) throws {
            profile = try? CalibrationProfile(from: decoder)
        }
    }
}
