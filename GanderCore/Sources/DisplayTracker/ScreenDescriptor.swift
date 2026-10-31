import CoreGraphics
import Foundation
import GanderModels

/// A plain snapshot of one `NSScreen`: exactly the values `DisplayInfo` needs, already extracted.
///
/// `SystemScreens` fills these from real screens. Keeping the mapping to `DisplayInfo` / `DisplayLayout` here,
/// over plain values, makes it testable without `NSScreen`.
struct ScreenDescriptor: Sendable, Equatable {
    /// `CGDirectDisplayID` from `deviceDescription["NSScreenNumber"]`.
    var cgDisplayID: UInt32
    /// String form of `CGDisplayCreateUUIDFromDisplayID`, or `nil` when the system could not produce one.
    var uuidString: String?
    /// `NSScreen.localizedName`.
    var name: String
    /// `NSScreen.frame`, in global AppKit coordinates.
    var frame: CGRect
    /// `CGDisplayIsBuiltin(cgDisplayID) != 0`.
    var isBuiltIn: Bool
    /// `CGDisplayIsMain(cgDisplayID) != 0`.
    var isMain: Bool

    /// The stable identity: the display UUID, or `fallbackID` when there is no usable UUID.
    var stableID: DisplayID {
        if let uuidString, !uuidString.isEmpty {
            return DisplayID(uuidString)
        }
        return fallbackID
    }

    /// `"cg-<cgDisplayID>"`. Only unique within the current login session, so it is a last resort.
    var fallbackID: DisplayID {
        DisplayID("cg-\(cgDisplayID)")
    }

    /// The `DisplayInfo` for this screen, identified by `stableID`.
    var displayInfo: DisplayInfo {
        displayInfo(id: stableID)
    }

    /// The `DisplayInfo` for this screen under an explicit identity.
    func displayInfo(id: DisplayID) -> DisplayInfo {
        DisplayInfo(id: id, cgDisplayID: cgDisplayID, name: name, frame: frame, isBuiltIn: isBuiltIn, isMain: isMain)
    }

    /// Builds the layout for a set of screens. Always goes through `DisplayLayout(displays:)`, which sorts the
    /// displays and computes the fingerprint.
    ///
    /// `DisplayLayout.display(withID:)` and the gate test assume IDs are unique. If two screens report the same
    /// UUID (monitors that share vendor, model and serial), the later one falls back to its `"cg-<id>"` name
    /// instead of silently merging with the first.
    static func layout(from descriptors: [ScreenDescriptor]) -> DisplayLayout {
        var seen = Set<DisplayID>()
        var displays: [DisplayInfo] = []
        displays.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            var id = descriptor.stableID
            if !seen.insert(id).inserted {
                id = descriptor.fallbackID
                seen.insert(id)
            }
            displays.append(descriptor.displayInfo(id: id))
        }
        return DisplayLayout(displays: displays)
    }
}
