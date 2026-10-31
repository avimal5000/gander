import Foundation
import SwayModels
import Testing

@testable import PoseTraces

@Suite struct FileTraceStoreTests {
    /// A whole-second date, since the JSON format stores ISO-8601 dates without fractions.
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14T22:13:20Z

    private func makeTrace(id: UUID = UUID(), createdAt: Date? = nil) -> PoseTrace {
        var trace = SyntheticTraces.gateTrace(
            clusters: leftRightClusters,
            std: 2,
            samplesPerSegment: 5,
            rounds: 2,
            faceDropRate: 0.2,
            seed: 11
        )
        trace.id = id
        trace.createdAt = createdAt ?? fixedDate
        trace.notes = "Round trip"
        return trace
    }

    @Test func defaultDirectoryIsApplicationSupportSwayTraces() {
        let store = FileTraceStore()
        let expected = URL.applicationSupportDirectory.appending(path: "Gander/Traces", directoryHint: .isDirectory)
        #expect(store.directory.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test func explicitDirectoryIsUsed() {
        let url = URL(filePath: "/tmp/somewhere", directoryHint: .isDirectory)
        #expect(FileTraceStore(directory: url).directory == url)
    }

    @Test func fileNameCombinesLocalTimestampAndLowercasedIDPrefix() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        components.hour = 9
        components.minute = 5
        components.second = 3
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))  // local time
        let id = try #require(UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890"))
        let trace = makeTrace(id: id, createdAt: date)
        #expect(FileTraceStore.fileName(for: trace) == "20260307-090503-abcdef12.json")
    }

    @Test func missingDirectoryListsNothing() throws {
        try withTemporaryDirectory { url in
            let urls = try FileTraceStore(directory: url).list()
            #expect(urls.isEmpty)
        }
    }

    @Test func loadingAMissingFileThrowsIOError() {
        withTemporaryDirectory { url in
            let store = FileTraceStore(directory: url)
            do {
                _ = try store.load(url.appending(path: "nope.json", directoryHint: .notDirectory))
                Issue.record("Expected an error")
            } catch let error as TraceStoreError {
                guard case .io = error else {
                    Issue.record("Expected .io, got \(error)")
                    return
                }
            } catch {
                Issue.record("Unexpected error type \(error)")
            }
        }
    }

    @Test func loadingGarbageThrowsDecodingError() throws {
        try withTemporaryDirectory { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let file = url.appending(path: "bad.json", directoryHint: .notDirectory)
            try Data("{ \"not\": \"a trace\" }".utf8).write(to: file)
            let store = FileTraceStore(directory: url)
            do {
                _ = try store.load(file)
                Issue.record("Expected an error")
            } catch let error as TraceStoreError {
                guard case .decoding(let message) = error else {
                    Issue.record("Expected .decoding, got \(error)")
                    return
                }
                #expect(!message.isEmpty)
            }
        }
    }

    @Test func listIgnoresNonJSONFilesAndSortsNewestFirst() throws {
        try withTemporaryDirectory { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for name in [
                "20240101-000000-aaaaaaaa.json", "20250101-000000-bbbbbbbb.json", "notes.txt",
                "20240601-120000-cccccccc.json",
            ] {
                try Data("{}".utf8).write(to: url.appending(path: name, directoryHint: .notDirectory))
            }
            let names = try FileTraceStore(directory: url).list().map(\.lastPathComponent)
            #expect(
                names == [
                    "20250101-000000-bbbbbbbb.json", "20240601-120000-cccccccc.json", "20240101-000000-aaaaaaaa.json",
                ]
            )
        }
    }

    #if DEBUG
    @Test func saveThenLoadRoundTripsTheTrace() throws {
        try withTemporaryDirectory { url in
            let store = FileTraceStore(directory: url)  // the folder does not exist yet; save creates it
            let trace = makeTrace()
            let saved = try store.save(trace)
            #expect(saved.deletingLastPathComponent().standardizedFileURL == url.standardizedFileURL)
            #expect(saved.lastPathComponent == FileTraceStore.fileName(for: trace))
            let loaded = try store.load(saved)
            let listed = try store.list()
            #expect(loaded == trace)
            // The temporary folder is reached through a symlink (/var), so compare by file name.
            #expect(listed.map(\.lastPathComponent) == [saved.lastPathComponent])
        }
    }

    @Test func savedJSONIsPrettyPrintedWithSortedKeysAndISODates() throws {
        try withTemporaryDirectory { url in
            let saved = try FileTraceStore(directory: url).save(makeTrace())
            let text = try String(contentsOf: saved, encoding: .utf8)
            #expect(text.contains("\n  \"cameraName\" : \"Synthetic\""))
            #expect(text.contains("\"createdAt\" : \"2023-11-14T22:13:20Z\""))
            let keys = ["cameraName", "createdAt", "formatVersion", "id", "layout", "notes", "segments"]
            let positions = try keys.map { key in
                try #require(text.range(of: "\n  \"\(key)\" :")).lowerBound
            }
            #expect(positions == positions.sorted())
        }
    }

    @Test func listIsNewestFirstAfterSavingSeveralTraces() throws {
        try withTemporaryDirectory { url in
            let store = FileTraceStore(directory: url)
            let oldest = try store.save(makeTrace(createdAt: fixedDate))
            let newest = try store.save(makeTrace(createdAt: fixedDate.addingTimeInterval(3600)))
            let middle = try store.save(makeTrace(createdAt: fixedDate.addingTimeInterval(60)))
            let listed = try store.list()
            #expect(listed.map(\.lastPathComponent) == [newest, middle, oldest].map(\.lastPathComponent))
        }
    }

    @Test func savingTheSameTraceTwiceOverwritesInsteadOfDuplicating() throws {
        try withTemporaryDirectory { url in
            let store = FileTraceStore(directory: url)
            let trace = makeTrace()
            let first = try store.save(trace)
            let second = try store.save(trace)
            let listed = try store.list()
            // No leftover temporary files from the atomic write.
            let allFiles = try FileManager.default.contentsOfDirectory(atPath: url.path)
            #expect(first == second)
            #expect(listed.count == 1)
            #expect(allFiles.count == 1)
        }
    }

    @Test func saveReportsIOErrorWhenTheFolderCannotBeCreated() throws {
        try withTemporaryDirectory { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let blocker = url.appending(path: "blocker", directoryHint: .notDirectory)
            try Data().write(to: blocker)
            // A path below a regular file can never be a folder.
            let store = FileTraceStore(directory: blocker.appending(path: "Traces", directoryHint: .isDirectory))
            do {
                _ = try store.save(makeTrace())
                Issue.record("Expected an error")
            } catch let error as TraceStoreError {
                guard case .io = error else {
                    Issue.record("Expected .io, got \(error)")
                    return
                }
            }
        }
    }
    #else
    @Test func saveWritesNothingAndThrowsInReleaseBuilds() throws {
        try withTemporaryDirectory { url in
            let store = FileTraceStore(directory: url)
            #expect(throws: TraceStoreError.disabledInReleaseBuilds) {
                try store.save(makeTrace())
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
    #endif
}
