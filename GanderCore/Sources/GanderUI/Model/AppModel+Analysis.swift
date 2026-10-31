import Foundation
import GanderModels

// Analysis results: adopting a report, the live guess, opening saved traces, and copying the summary.
extension AppModel {
    /// The report whose clusters drive the live guess: the best feature set of the latest analysis.
    var liveReport: SeparabilityReport? {
        guard let analysis, let best = analysis.bestFeatureSet else { return nil }
        return analysis.report(for: best)
    }

    /// The label of the display the live guess points at.
    var liveGuessName: String? {
        guard let classification = liveClassification else { return nil }
        return analysisLabels[classification.displayID]
            ?? liveReport?.displays.first { $0.displayID == classification.displayID }?.displayName
    }

    /// Makes `result` the analysis on screen and the source of the live guess.
    func adopt(_ result: GateAnalysis, trace: PoseTrace, source: AnalysisSource) {
        analysis = result
        analysisTrace = trace
        analysisSource = source
        analysisLabels = Self.labels(for: result)
        reportFeatureSet = result.bestFeatureSet ?? result.reports.first?.featureSet ?? .visionAngles
        didCopySummary = false
        updateLiveClassification(for: latestSample?.pose)
    }

    private static func labels(for result: GateAnalysis) -> [DisplayID: String] {
        // Every report lists the same displays; the first is enough.
        guard let report = result.reports.first else { return [:] }
        return DisplayLabeler.labels(for: report.displays.map { (id: $0.displayID, name: $0.displayName) })
    }

    /// Reclassifies the latest pose under the best feature set's report.
    ///
    /// Landmark angles exist only during the gate test, so when the best set is the landmark one the live pose
    /// usually lacks its features. The classifier then returns `nil` and the Vision-angles report is used instead.
    func updateLiveClassification(for pose: HeadPose?) {
        var updated: DisplayClassification?
        var usedFeatureSet: PoseFeatureSet?
        if let pose, let analysis, let best = analysis.bestFeatureSet {
            let candidates: [PoseFeatureSet] = best == .visionAngles ? [best] : [best, .visionAngles]
            for featureSet in candidates {
                guard let report = analysis.report(for: featureSet),
                    let classification = analyzer.classify(pose, using: report)
                else { continue }
                updated = classification
                usedFeatureSet = featureSet
                break
            }
        }
        if updated != liveClassification { liveClassification = updated }
        if usedFeatureSet != liveGuessFeatureSet { liveGuessFeatureSet = usedFeatureSet }
    }

    /// Shows an open panel in the trace folder, then analyzes the chosen file.
    func openTrace() {
        guard gateRunState == .idle else { return }
        guard let url = environment.system.chooseTraceFile(startingIn: traceStore.directory) else { return }
        openTrace(at: url)
    }

    /// Loads and analyzes a saved trace; it becomes the latest analysis (SPEC F9).
    func openTrace(at url: URL) {
        do {
            let trace = try traceStore.load(url)
            let result = analyzer.analyze(trace, thresholds: .default)
            adopt(result, trace: trace, source: .file(url))
            refitCalibration(from: trace)
            traceSaveStatus = .none
            gateMessage = nil
            isShowingReport = true
        } catch {
            log.error("Opening a trace failed: \(String(describing: error), privacy: .public)")
            gateMessage = .error("Could not open \(url.lastPathComponent). \(userMessage(for: error))")
        }
    }

    /// Copies the Markdown summary of the report on screen to the pasteboard.
    func copyMarkdownSummary() {
        guard let analysis, let trace = analysisTrace else { return }
        environment.system.copyToPasteboard(analyzer.markdownSummary(of: analysis, trace: trace))
        didCopySummary = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.didCopySummary = false
        }
    }

    /// Selects a saved trace file in Finder.
    func revealInFinder(_ url: URL) {
        environment.system.revealInFinder(url)
    }
}
