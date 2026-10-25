import SwayModels
import SwiftUI

/// The separability report (SPEC F8): overall verdict, one tab per feature set, and the export actions.
struct GateReportView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let analysis = model.analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(analysis)
                    actions
                    saveStatus
                    calibrationStatus
                    if let message = model.gateMessage { MessageView(message: message) }
                    Picker("Feature set", selection: $model.reportFeatureSet) {
                        ForEach(analysis.reports, id: \.featureSet) { report in
                            Text("\(report.featureSet.title) \u{00B7} \(report.verdict.title)").tag(report.featureSet)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if let report = analysis.report(for: model.reportFeatureSet) {
                        FeatureReportView(model: model, report: report, thresholds: analysis.thresholds)
                    }
                }
                .padding(20)
            }
        }
    }

    private func header(_ analysis: GateAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Gate result")
                    .font(.title2.weight(.semibold))
                VerdictBadge(verdict: analysis.overall, large: true)
            }
            Text(analysis.overall.explanation)
            if let best = analysis.bestFeatureSet {
                Text("Best signal: \(best.title).")
                    .foregroundStyle(.secondary)
            }
            Text(sourceLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceLine: String {
        var parts: [String] = []
        switch model.analysisSource {
        case .gateTest: parts.append("Gate test just run")
        case .file(let url): parts.append("Loaded from \(url.lastPathComponent)")
        case nil: break
        }
        if let trace = model.analysisTrace {
            if let camera = trace.cameraName { parts.append(camera) }
            parts.append(trace.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var actions: some View {
        HStack {
            Button {
                model.copyMarkdownSummary()
            } label: {
                Label(
                    model.didCopySummary ? "Copied" : "Copy Markdown Summary",
                    systemImage: model.didCopySummary ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.borderedProminent)
            Button("Open Trace\u{2026}") { model.openTrace() }
            Button("Run Again") { model.showGateSetup() }
        }
    }

    /// Whether this trace produced a calibration that was saved in the library, or why not.
    @ViewBuilder
    private var calibrationStatus: some View {
        if let message = model.calibrationMessage {
            VStack(alignment: .leading, spacing: 2) {
                MessageView(message: message)
                if model.activeCalibration != nil {
                    Text("Your previous calibration is still in use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let profile = model.lastFittedProfile {
            Label(
                "Calibration saved for \(profile.displays.count) displays. Turn Tracking on in the menu to use it.",
                systemImage: "checkmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        switch model.traceSaveStatus {
        case .none:
            EmptyView()
        case .saved(let url):
            HStack {
                Label("Trace saved: \(url.lastPathComponent)", systemImage: "square.and.arrow.down")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Reveal in Finder") { model.revealInFinder(url) }
            }
        case .failed(let message):
            MessageView(message: .error("The trace could not be saved. \(message)"))
        case .disabledInRelease:
            Label("Traces are only saved in debug builds.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
