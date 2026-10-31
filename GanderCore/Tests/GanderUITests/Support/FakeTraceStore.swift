import Foundation
import GanderModels
import os

/// An in-memory trace store.
final class FakeTraceStore: TraceStoring {
    struct State: Sendable {
        var saved: [PoseTrace] = []
        var saveError: TraceStoreError?
        var loadable: [URL: PoseTrace] = [:]
        var loadError: TraceStoreError?
    }

    let directory: URL
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(directory: URL = URL(fileURLWithPath: "/tmp/gander-ui-tests/traces")) {
        self.directory = directory
    }

    var saved: [PoseTrace] { state.withLock { $0.saved } }

    func setSaveError(_ error: TraceStoreError?) {
        state.withLock { $0.saveError = error }
    }

    func setLoadable(_ trace: PoseTrace, at url: URL) {
        state.withLock { $0.loadable[url] = trace }
    }

    func setLoadError(_ error: TraceStoreError?) {
        state.withLock { $0.loadError = error }
    }

    func save(_ trace: PoseTrace) throws -> URL {
        try state.withLock { state in
            if let error = state.saveError { throw error }
            state.saved.append(trace)
            return directory.appendingPathComponent("trace-\(state.saved.count).json")
        }
    }

    func load(_ url: URL) throws -> PoseTrace {
        try state.withLock { state in
            if let error = state.loadError { throw error }
            guard let trace = state.loadable[url] else { throw TraceStoreError.io("missing file") }
            return trace
        }
    }

    func list() throws -> [URL] { [] }
}
