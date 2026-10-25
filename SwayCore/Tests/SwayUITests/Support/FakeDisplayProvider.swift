import Foundation
import SwayModels

/// A display provider with a settable layout and a stream the test can push into.
@MainActor
final class FakeDisplayProvider: DisplayProviding {
    var currentLayout: DisplayLayout
    private var continuations: [AsyncStream<DisplayLayout>.Continuation] = []

    init(layout: DisplayLayout) {
        currentLayout = layout
    }

    func layouts() -> AsyncStream<DisplayLayout> {
        let (stream, continuation) = AsyncStream<DisplayLayout>.makeStream()
        continuation.yield(currentLayout)
        continuations.append(continuation)
        return stream
    }

    /// Changes the layout and tells every stream.
    func change(to layout: DisplayLayout) {
        currentLayout = layout
        for continuation in continuations { continuation.yield(layout) }
    }
}
