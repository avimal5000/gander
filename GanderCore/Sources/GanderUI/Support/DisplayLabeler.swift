import GanderModels

/// Builds unique, human-readable labels for displays. Two identical monitors share a name, so duplicates get a
/// numeric suffix in the order given ("Studio Display (1)", "Studio Display (2)").
enum DisplayLabeler {
    static func labels(for entries: [(id: DisplayID, name: String)]) -> [DisplayID: String] {
        var totals: [String: Int] = [:]
        for entry in entries { totals[entry.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var result: [DisplayID: String] = [:]
        for entry in entries {
            if totals[entry.name, default: 0] > 1 {
                seen[entry.name, default: 0] += 1
                result[entry.id] = "\(entry.name) (\(seen[entry.name, default: 0]))"
            } else {
                result[entry.id] = entry.name
            }
        }
        return result
    }

    /// Labels for the displays of a layout.
    static func labels(for layout: DisplayLayout) -> [DisplayID: String] {
        labels(for: layout.displays.map { (id: $0.id, name: $0.name) })
    }
}
