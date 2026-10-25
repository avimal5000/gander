import Foundation
import SwayModels
import Testing

@testable import SwayUI

@MainActor
@Suite("AppModel analysis")
struct AppModelAnalysisTests {
    private let nearLeft = DisplayClassification(displayID: Fixtures.left.id, distance: 0.8, runnerUpDistance: 9.5)

    // MARK: Live guess

    @Test func theLiveGuessUsesTheBestFeatureSetsReport() {
        let h = Harness.make(analysis: Fixtures.analysis(best: .landmarkAngles))
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)

        h.model.adopt(Fixtures.analysis(best: .landmarkAngles), trace: Fixtures.trace(), source: .gateTest)
        h.feed(yaw: -20)

        #expect(h.analyzer.classifiedReports.last?.featureSet == .landmarkAngles)
        #expect(h.model.liveReport?.featureSet == .landmarkAngles)
        #expect(h.model.liveClassification == nearLeft)
        #expect(h.model.liveGuessName == "Left")
    }

    @Test func theBestFeatureSetCanBeVision() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)

        h.model.adopt(Fixtures.analysis(best: .visionAngles), trace: Fixtures.trace(), source: .gateTest)
        h.feed()

        #expect(h.analyzer.classifiedReports.last?.featureSet == .visionAngles)
    }

    @Test func aBestLandmarkReportFallsBackToVisionWhenThePoseHasNoLandmarks() {
        let h = Harness.make(analysis: Fixtures.analysis(best: .landmarkAngles))
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)
        h.analyzer.setUnclassifiable(.landmarkAngles)
        h.model.adopt(Fixtures.analysis(best: .landmarkAngles), trace: Fixtures.trace(), source: .gateTest)

        h.feed(yaw: -20)

        #expect(h.analyzer.classifiedReports.map(\.featureSet).suffix(2) == [.landmarkAngles, .visionAngles])
        #expect(h.model.liveClassification == nearLeft)
        #expect(h.model.liveGuessFeatureSet == .visionAngles)
        #expect(h.model.liveGuessName == "Left")
    }

    @Test func aBestLandmarkReportIsUsedWhileTheLandmarksExist() {
        let h = Harness.make(analysis: Fixtures.analysis(best: .landmarkAngles))
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)
        h.model.adopt(Fixtures.analysis(best: .landmarkAngles), trace: Fixtures.trace(), source: .gateTest)
        let before = h.analyzer.classifiedReports.count

        h.feed()

        #expect(h.analyzer.classifiedReports.count == before + 1)
        #expect(h.analyzer.classifiedReports.last?.featureSet == .landmarkAngles)
        #expect(h.model.liveGuessFeatureSet == .landmarkAngles)
    }

    @Test func aVisionReportThatCannotClassifyHasNoFallbackAndNoGuess() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setUnclassifiable(.visionAngles)
        h.model.adopt(Fixtures.analysis(best: .visionAngles), trace: Fixtures.trace(), source: .gateTest)
        let before = h.analyzer.classifiedReports.count

        h.feed()

        #expect(h.analyzer.classifiedReports.count == before + 1)
        #expect(h.model.liveClassification == nil)
        #expect(h.model.liveGuessFeatureSet == nil)
    }

    @Test func noFaceMeansNoGuess() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)
        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)

        h.feed()
        #expect(h.model.liveClassification != nil)
        let callsBefore = h.analyzer.classifiedReports.count

        h.feed(face: false)
        #expect(h.model.liveClassification == nil)
        #expect(h.model.liveGuessName == nil)
        #expect(h.analyzer.classifiedReports.count == callsBefore)
    }

    @Test func thereIsNoGuessBeforeAnyAnalysis() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)

        h.feed()

        #expect(h.model.liveClassification == nil)
        #expect(h.analyzer.classifiedReports.isEmpty)
    }

    @Test func adoptingAnAnalysisReclassifiesTheLatestPoseImmediately() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)
        h.feed()
        #expect(h.model.liveClassification == nil)

        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)
        #expect(h.model.liveClassification == nearLeft)
    }

    @Test func aGuessLosesItsNameLabelWhenTheReportDoesNotKnowTheDisplay() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(DisplayClassification(displayID: "stranger", distance: 1, runnerUpDistance: nil))
        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)
        h.feed()
        #expect(h.model.liveClassification?.displayID == "stranger")
        #expect(h.model.liveGuessName == nil)
    }

    // MARK: Opening traces

    @Test func openingATraceAnalyzesItAndMakesItTheLatestAnalysis() {
        let h = Harness.make()
        defer { h.tearDown() }
        let url = URL(fileURLWithPath: "/tmp/sway-ui-tests/saved.json")
        let trace = Fixtures.trace()
        h.store.setLoadable(trace, at: url)

        h.model.openTrace(at: url)

        #expect(h.model.analysis == Fixtures.analysis())
        #expect(h.model.analysisTrace == trace)
        #expect(h.model.analysisSource == .file(url))
        #expect(h.model.isShowingReport)
        #expect(h.analyzer.analyzedTraces == [trace])
        #expect(h.analyzer.analyzedThresholds == [.default])
        #expect(h.model.traceSaveStatus == .none)
        #expect(h.model.gateMessage == nil)
    }

    @Test func anOpenedTraceFeedsTheLiveGuess() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.analyzer.setClassification(nearLeft)
        let url = URL(fileURLWithPath: "/tmp/sway-ui-tests/saved.json")
        h.store.setLoadable(Fixtures.trace(), at: url)

        h.model.openTrace(at: url)
        h.feed()

        #expect(h.model.liveClassification == nearLeft)
    }

    @Test func openingChoosesAFileStartingInTheTraceFolder() {
        let h = Harness.make()
        defer { h.tearDown() }
        let url = URL(fileURLWithPath: "/tmp/sway-ui-tests/picked.json")
        h.store.setLoadable(Fixtures.trace(), at: url)
        h.system.chosenFile = url

        h.model.openTrace()

        #expect(h.system.chooserDirectories == [h.store.directory])
        #expect(h.model.analysisSource == .file(url))
    }

    @Test func cancellingTheOpenPanelChangesNothing() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.system.chosenFile = nil

        h.model.openTrace()

        #expect(h.model.analysis == nil)
        #expect(h.model.gateMessage == nil)
        #expect(h.analyzer.analyzedTraces.isEmpty)
    }

    @Test func aTraceThatCannotBeReadShowsAnError() {
        let h = Harness.make()
        defer { h.tearDown() }
        let url = URL(fileURLWithPath: "/tmp/sway-ui-tests/broken.json")
        h.store.setLoadError(.decoding("missing key"))

        h.model.openTrace(at: url)

        #expect(h.model.analysis == nil)
        #expect(!h.model.isShowingReport)
        #expect(h.model.gateMessage?.kind == .error)
        #expect(h.model.gateMessage?.text.contains("broken.json") == true)
        #expect(h.model.gateMessage?.text.contains("missing key") == true)
    }

    @Test func aFailedOpenKeepsThePreviousReport() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)
        h.store.setLoadError(.io("gone"))

        h.model.openTrace(at: URL(fileURLWithPath: "/tmp/sway-ui-tests/gone.json"))

        #expect(h.model.analysis != nil)
        #expect(h.model.analysisSource == .gateTest)
    }

    // MARK: Copying

    @Test func copyingPutsTheAnalyzersMarkdownOnThePasteboard() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.adopt(Fixtures.analysis(), trace: Fixtures.trace(), source: .gateTest)

        h.model.copyMarkdownSummary()

        #expect(h.system.copied == ["FAKE MARKDOWN"])
        #expect(h.model.didCopySummary)
    }

    @Test func copyingWithoutAnAnalysisDoesNothing() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.copyMarkdownSummary()
        #expect(h.system.copied.isEmpty)
        #expect(!h.model.didCopySummary)
    }

    @Test func adoptingAReportPicksItsBestFeatureSetTab() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.adopt(Fixtures.analysis(best: .landmarkAngles), trace: Fixtures.trace(), source: .gateTest)
        #expect(h.model.reportFeatureSet == .landmarkAngles)
        h.model.adopt(Fixtures.analysis(best: .visionAngles), trace: Fixtures.trace(), source: .gateTest)
        #expect(h.model.reportFeatureSet == .visionAngles)
    }

    @Test func revealInFinderIsForwardedToTheDesktop() {
        let h = Harness.make()
        defer { h.tearDown() }
        let url = URL(fileURLWithPath: "/tmp/sway-ui-tests/x.json")
        h.model.revealInFinder(url)
        #expect(h.system.revealed == [url])
    }

    // MARK: Free recording (debug builds)

    #if DEBUG
    @Test func recordingSavesAnUnlabeledSegmentOfTheLiveSamples() async throws {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.model.startRecording()
        #expect(h.model.recorder.isRecording)
        h.run(frames: 5, dt: 0.1)
        h.run(frames: 2, dt: 0.1, face: false)
        #expect(h.model.recorder.sampleCount == 7)

        h.model.stopRecording()

        #expect(!h.model.recorder.isRecording)
        let trace = try #require(h.store.saved.first)
        #expect(trace.segments.count == 1)
        #expect(trace.segments[0].displayID == nil)
        #expect(trace.segments[0].round == 0)
        #expect(trace.segments[0].samples.count == 7)
        #expect(trace.segments[0].samples.filter { $0.pose == nil }.count == 2)
        #expect(trace.cameraName == "FaceTime HD Camera")
        if case .saved(let url)? = h.model.recorder.lastResult {
            #expect(url.lastPathComponent == "trace-1.json")
        } else {
            Issue.record("Expected a saved recording")
        }
    }

    @Test func recordingNeedsTheCamera() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.model.startRecording()
        #expect(!h.model.recorder.isRecording)
    }

    @Test func aSaveFailureIsShownAndNothingIsClaimedSaved() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        h.store.setSaveError(.io("read-only volume"))
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.model.startRecording()
        h.run(frames: 3, dt: 0.1)
        h.model.stopRecording()

        if case .failed(let message)? = h.model.recorder.lastResult {
            #expect(message.contains("read-only volume"))
        } else {
            Issue.record("Expected a failed recording")
        }
    }

    @Test func stoppingWithoutSamplesReportsThat() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }

        h.model.startRecording()
        h.model.stopRecording()

        #expect(h.store.saved.isEmpty)
        #expect(h.model.recorder.lastResult == .failed("No samples were recorded."))
    }

    @Test func turningTheCameraOffSavesAnActiveRecording() async {
        let h = Harness.make(autoRun: true, calibrated: true)
        defer { h.tearDown() }
        await h.model.setTrackingEnabled(true)
        _ = await waitUntil { h.model.status.isRunning }
        h.model.startRecording()
        h.run(frames: 4, dt: 0.1)

        await h.model.setTrackingEnabled(false)

        #expect(!h.model.recorder.isRecording)
        #expect(h.store.saved.count == 1)
    }
    #endif
}
