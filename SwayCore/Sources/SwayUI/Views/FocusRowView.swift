import SwayModels
import SwiftUI

/// One display in the Focus Test window: its name, its last-used window, and the two focus buttons.
struct FocusRowView: View {
    let model: AppModel
    let row: FocusTestPresentation.Row

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.headline)
                Text(row.windowText)
                    .font(.callout)
                    .foregroundStyle(row.hasWindow ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            if model.focusActivity == .focusing(display: row.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Focusing")
            }
            Button("Focus") { model.focusNow(row.id) }
                .disabled(!model.canRequestFocus)
            delayedButton
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var delayedButton: some View {
        if case .countingDown(let display, _) = model.focusActivity, display == row.id {
            Button("Cancel (\(model.focusCountdownSeconds) s)") { model.cancelDelayedFocus() }
        } else {
            Button("Focus in 3 s") { model.focusAfterDelay(row.id) }
                .disabled(!model.canRequestFocus)
        }
    }
}
