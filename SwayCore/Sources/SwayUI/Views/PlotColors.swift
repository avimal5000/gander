import SwiftUI

/// Maps display labels to series colors for Swift Charts.
struct PlotColors {
    let domain: [String]
    let range: [Color]

    init(labels: [String]) {
        domain = labels
        range = labels.indices.map { SwayPalette.seriesColor(at: $0) }
    }
}
