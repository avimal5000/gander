import Foundation
import SwayModels

/// The pure translations between the system's login item state and Sway's `LoginItemStatus`, plus the wording of
/// the errors the user sees.
enum LoginItemMapping {
    static let notFoundMessage =
        "macOS can't find this copy of Sway. Move Sway to the Applications folder, open it from there, and try again."
    static let unknownStateMessage = "macOS reported an unknown login item state."

    /// The status Sway shows for a system state.
    static func status(for state: LoginItemSystemState) -> LoginItemStatus {
        switch state {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable(notFoundMessage)
        case .unknown: .unavailable(unknownStateMessage)
        }
    }

    /// A plain sentence for a failed register or unregister call, ending with the system's own description.
    static func failureMessage(enabling: Bool, systemDescription: String) -> String {
        let lead = "Sway couldn't \(enabling ? "turn on" : "turn off") opening at login."
        let detail = systemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return lead }
        let endsSentence = detail.last.map { ".!?".contains($0) } ?? false
        return "\(lead) macOS said: \(detail)\(endsSentence ? "" : ".")"
    }
}
