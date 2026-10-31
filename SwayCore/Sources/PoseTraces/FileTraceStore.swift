import Foundation
import SwayModels
import os

/// Persists numeric pose traces as pretty-printed JSON files in a folder.
///
/// Saving is only available in DEBUG builds (privacy guarantee); loading and listing work in every build
/// configuration so that a saved trace can always be re-analyzed.
public struct FileTraceStore: TraceStoring {
    /// Folder holding the trace files.
    public let directory: URL

    /// Largest trace file `load` reads. A real trace is well under 10 MB; anything bigger is refused unread.
    public static let maxFileBytes = 50 * 1024 * 1024

    private static let log = SwayLog.logger(category: "traces")

    /// Creates a store.
    /// - Parameter directory: folder for trace files; `nil` selects `Application Support/Sway/Traces`.
    public init(directory: URL? = nil) {
        self.directory =
            directory ?? URL.applicationSupportDirectory.appending(path: "Sway/Traces", directoryHint: .isDirectory)
    }

    /// Writes `trace` atomically as `yyyyMMdd-HHmmss-<first 8 of id>.json` and returns the file URL.
    ///
    /// In non-DEBUG builds nothing is written (not even the folder) and `.disabledInReleaseBuilds` is thrown.
    /// - Throws: `TraceStoreError.io` when the folder cannot be created or the file cannot be written.
    public func save(_ trace: PoseTrace) throws -> URL {
        #if DEBUG
        let url = directory.appending(path: Self.fileName(for: trace), directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try Self.makeEncoder().encode(trace)
            try data.write(to: url, options: .atomic)
            // Owner-only: traces hold display and camera names and timed head angles.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Self.log.error("Saving trace failed: \(error.localizedDescription, privacy: .public)")
            throw TraceStoreError.io(Self.describe(error))
        }
        Self.log.info("Saved trace \(url.lastPathComponent, privacy: .public)")
        return url
        #else
        throw TraceStoreError.disabledInReleaseBuilds
        #endif
    }

    /// Reads a trace file. Works in every build configuration.
    /// - Throws: `TraceStoreError.io` when the file cannot be read, `.decoding` when it is not a valid trace.
    public func load(_ url: URL) throws -> PoseTrace {
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maxFileBytes else {
                throw TraceStoreError.io("The file is too large to be a trace (\(size / 1_048_576) MB).")
            }
            data = try Data(contentsOf: url)
        } catch let error as TraceStoreError {
            throw error
        } catch {
            throw TraceStoreError.io(Self.describe(error))
        }
        do {
            return try Self.makeDecoder().decode(PoseTrace.self, from: data)
        } catch {
            throw TraceStoreError.decoding(Self.describe(error))
        }
    }

    /// The `.json` files in `directory`, sorted by file name descending (newest first).
    /// Returns an empty array when the folder does not exist.
    /// - Throws: `TraceStoreError.io` when the folder exists but cannot be read.
    public func list() throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return []
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return
                contents
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            throw TraceStoreError.io(Self.describe(error))
        }
    }

    // MARK: - Internals

    /// `yyyyMMdd-HHmmss-<first 8 chars of the trace id, lowercased>.json`, using the creation date in local time.
    static func fileName(for trace: PoseTrace) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let idPrefix = trace.id.uuidString.lowercased().prefix(8)
        return "\(formatter.string(from: trace.createdAt))-\(idPrefix).json"
    }

    /// Pretty-printed, key-sorted JSON with ISO-8601 dates (whole seconds).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder matching `makeEncoder()`.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A readable one-line description of an I/O or decoding error, including the coding path for decoding errors.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ context: DecodingError.Context) -> String {
            let components = context.codingPath.map(\.stringValue)
            return components.isEmpty ? "" : " at \(components.joined(separator: "."))"
        }
        switch decodingError {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription)\(path(context))"
        case .keyNotFound(let key, let context):
            return "Missing key \(key.stringValue)\(path(context))"
        @unknown default:
            return "Invalid trace data"
        }
    }
}
