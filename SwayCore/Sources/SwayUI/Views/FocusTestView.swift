import SwayModels
import SwiftUI

/// The Focus Test window (SPEC F13): Accessibility status, each display's last-used window with focus buttons, and a
/// log of the last results. Window titles are shown here and nowhere else.
struct FocusTestView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Focus test")
                    .font(.title2.weight(.semibold))
                AccessibilityOnboardingView(model: model)
                displaysCard
                logCard
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 480)
        .tint(model.accentChoice.tint)
        .onAppear { model.startFocusTest() }
        .onDisappear { model.stopFocusTest() }
        .launchGuarded(id: SwayWindowID.focusTest, model: model)
    }

    private var displaysCard: some View {
        let rows = FocusTestPresentation.rows(
            layout: model.layout, windows: model.focusWindows, focused: model.focusedDisplayID)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Displays (left to right)")
                .font(.headline)
            if rows.isEmpty {
                Text("No displays found.").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                FocusRowView(model: model, row: row)
                if row.id != rows.last?.id { Divider() }
            }
            Text(
                "Focus raises the last-used window on that display and gives it keyboard focus. "
                    + "Focus in 3 s waits first, so you can click into another app. The cursor never moves."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .swayCard()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Results")
                .font(.headline)
            if model.focusLog.isEmpty {
                Text("Results appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.focusLog) { entry in
                HStack(spacing: 10) {
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .swayCard()
    }
}

#if DEBUG
#Preview("Focus test, granted") {
    FocusTestView(model: PreviewSupport.model(focusTrusted: true))
}

#Preview("Focus test, not granted") {
    FocusTestView(model: PreviewSupport.model(focusTrusted: false))
}
#endif
