import GanderModels

@testable import GanderUI

/// Records the edge glow and notice requests instead of showing panels.
@MainActor
final class FakeFeedback: FeedbackPresenting {
    struct Glow: Equatable {
        let display: DisplayInfo
        let animated: Bool
    }

    struct Notice: Equatable {
        let text: String
        let symbol: String
        let display: DisplayInfo
        let animated: Bool
    }

    private(set) var glows: [Glow] = []
    private(set) var notices: [Notice] = []

    func showGlow(on display: DisplayInfo, animated: Bool) {
        glows.append(Glow(display: display, animated: animated))
    }

    func showNotice(_ text: String, symbol: String, on display: DisplayInfo, animated: Bool) {
        notices.append(Notice(text: text, symbol: symbol, display: display, animated: animated))
    }
}
