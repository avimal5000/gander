import SwiftUI

/// The Focus Lock switch (SPEC F17), with its shortcut shown beside it when `showsShortcut` is set. Shared by the menu
/// and the debug window.
struct FocusLockToggle: View {
    let model: AppModel
    var showsShortcut = true

    var body: some View {
        Toggle(isOn: binding) {
            HStack {
                Text("Focus Lock")
                if showsShortcut, let shortcut = model.focusLockShortcut {
                    Spacer()
                    Text(shortcut.displayString)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .help("While on, the camera keeps running but focus never switches by itself.")
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { model.focusLocked },
            set: { model.setFocusLock($0) }
        )
    }
}
