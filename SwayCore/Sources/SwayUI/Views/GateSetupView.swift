import SwayModels
import SwiftUI

/// Pre-test form: the connected displays, rounds, hold time, and the Start button.
struct GateSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Head-pose gate test")
                        .font(.title2.weight(.semibold))
                    Text(
                        "A green overlay appears on each display in turn. Look at its center and hold still. "
                            + "Sway checks whether your head pose tells the displays apart. Nothing leaves your Mac."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                CameraPermissionView(model: model)
                displaysCard
                settingsCard
                if let message = model.gateMessage { MessageView(message: message) }
                actions
            }
            .padding(20)
        }
    }

    private var displaysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Displays (left to right)")
                .font(.headline)
            if model.layout.displays.isEmpty {
                Text("No displays found.").foregroundStyle(.secondary)
            }
            ForEach(Array(model.layout.displays.enumerated()), id: \.element.id) { index, display in
                HStack {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(SwayPalette.seriesColor(at: index).opacity(0.25), in: Circle())
                        .accessibilityHidden(true)
                    Text(display.name)
                    Spacer()
                    Text(detail(for: display))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !model.canRunGateTest {
                MessageView(
                    message: .error("The gate test needs at least 2 displays. Connect another display to continue.")
                )
            } else if model.exceedsTrackedDisplays {
                MessageView(
                    message: .info(
                        "Sway v1 will track \(SwayPolicy.maxTrackedDisplays) displays. "
                            + "This test measures all \(model.layout.displays.count) connected displays."
                    )
                )
            }
        }
        .swayCard()
    }

    private func detail(for display: DisplayInfo) -> String {
        var parts = ["\(Int(display.frame.width)) \u{00D7} \(Int(display.frame.height)) pt"]
        if display.isBuiltIn { parts.append("built-in") }
        if display.isMain { parts.append("main") }
        return parts.joined(separator: ", ")
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)
            Stepper(
                "Rounds: \(model.gateConfiguration.rounds)",
                value: $model.gateConfiguration.rounds,
                in: GateTestConfiguration.roundsRange
            )
            Stepper(
                "Hold time: \(Int(model.gateConfiguration.holdDuration)) s per display",
                value: $model.gateConfiguration.holdDuration,
                in: GateTestConfiguration.holdRange,
                step: 1
            )
            CameraPickerView(model: model)
            Text(
                "About "
                    + Formatting.seconds(
                        model.gateConfiguration.estimatedDuration(displayCount: model.layout.displays.count))
                    + ", including a short countdown before each hold. The camera turns on for the test and returns "
                    + "to its previous state afterwards."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .swayCard()
    }

    private var actions: some View {
        HStack {
            Button("Start test") { Task { await model.startGateTest() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRunGateTest || model.gateRunState != .idle)
            Button("Open Trace\u{2026}") { model.openTrace() }
            if model.analysis != nil {
                Button("View last report") { model.isShowingReport = true }
            }
        }
    }
}

/// An inline info or error message.
struct MessageView: View {
    let message: UserMessage

    var body: some View {
        Label(message.text, systemImage: message.kind == .error ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.callout)
            .foregroundStyle(message.kind == .error ? SwayPalette.brick : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
