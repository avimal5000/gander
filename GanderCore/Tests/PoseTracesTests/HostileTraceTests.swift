import CoreGraphics
import Foundation
import GanderModels
import Testing

@testable import PoseTraces

/// Security audit S2: a corrupt or crafted trace must never trap the app.
@Suite struct HostileTraceTests {
    private func trace(width: CGFloat, height: CGFloat, x: CGFloat = 0) -> PoseTrace {
        var trace = SyntheticTraces.gateTrace(
            clusters: leftRightClusters, std: 2, samplesPerSegment: 5, rounds: 1, seed: 3)
        let display = DisplayInfo(
            id: "A", cgDisplayID: 1, name: "Huge", frame: CGRect(x: x, y: x, width: width, height: height),
            isBuiltIn: false, isMain: true)
        trace.layout = DisplayLayout(displays: [display])
        return trace
    }

    @Test(arguments: [1e300, -1e300, Double.infinity, -Double.infinity, Double.nan, 9.3e18])
    func markdownSummaryDoesNotTrapOnHugeOrNonFiniteDisplaySizes(value: Double) {
        let hostile = trace(width: CGFloat(value), height: CGFloat(value), x: CGFloat(value))
        let analyzer = SeparabilityAnalyzer()
        let text = analyzer.markdownSummary(of: analyzer.analyze(hostile, thresholds: .default), trace: hostile)
        #expect(text.contains("Huge ("))
    }

    @Test func hugeFrameDecodedFromJSONDoesNotTrapTheFormatter() throws {
        let original = trace(width: 123_456, height: 100)
        var json = String(decoding: try FileTraceStore.makeEncoder().encode(original), as: UTF8.self)
        json = json.replacingOccurrences(of: "123456", with: "1e300")
        #expect(json.contains("1e300"))
        let decoded = try FileTraceStore.makeDecoder().decode(PoseTrace.self, from: Data(json.utf8))
        #expect(decoded.layout?.displays.first?.frame.width == 1e300)
        let analyzer = SeparabilityAnalyzer()
        let text = analyzer.markdownSummary(of: analyzer.analyze(decoded, thresholds: .default), trace: decoded)
        #expect(text.contains("Huge ("))
    }

    @Test func oversizedTraceFileIsRefusedBeforeItIsRead() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gander-big-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: FileTraceStore.maxFileBytes + 1).write(to: url)
        #expect(throws: TraceStoreError.self) { try FileTraceStore().load(url) }
        do {
            _ = try FileTraceStore().load(url)
        } catch TraceStoreError.io(let message) {
            #expect(message.contains("too large"))
        }
    }

    #if DEBUG
    @Test func savedTraceIsOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "gander-perm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = try FileTraceStore(directory: dir).save(trace(width: 100, height: 100))
        let file = try FileManager.default.attributesOfItem(atPath: saved.path)[.posixPermissions] as? Int
        let folder = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(file == 0o600)
        #expect(folder == 0o700)
    }
    #endif
}
