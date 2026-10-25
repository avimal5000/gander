import AppKit
import SwiftUI

/// Keeps a window that SwiftUI opens at launch from ever showing.
///
/// SwiftUI opens `Window` scenes when the app launches, which is wrong for a menu bar app. `SceneBuilder` cannot
/// branch on availability, so the macOS 15 `defaultLaunchBehavior(.suppressed)` cannot be used while the app
/// still deploys to macOS 14. Instead, a window that appears without a prior request from the menu is made fully
/// transparent the moment it gets its `NSWindow` (before it is drawn) and then closed with `dismissWindow`.
/// Windows the user asked for are revealed normally.
///
/// A request (`AppModel.noteWindowRequested`) stays in force until its window disappears, so the outcome does not
/// depend on whether SwiftUI runs `onAppear` before or after the guard view joins the window. The close is deferred
/// to the next main-actor turn so it never happens while SwiftUI is still presenting or laying out the window.
struct LaunchWindowGuard: NSViewRepresentable {
    let id: String
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        GuardView(id: id, model: model)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class GuardView: NSView {
        private let id: String
        private let model: AppModel

        init(id: String, model: AppModel) {
            self.id = id
            self.model = model
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            model.register(window: window, id: id)
            // Only the alpha changes here: no layout, no observable state.
            window.alphaValue = model.hasWindowRequest(id) ? 1 : 0
        }
    }
}

extension View {
    /// Applies the launch guard for window `id`: a window nobody asked for is closed unseen.
    func launchGuarded(id: String, model: AppModel) -> some View {
        modifier(LaunchGuardModifier(id: id, model: model))
    }
}

private struct LaunchGuardModifier: ViewModifier {
    let id: String
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content
            .background(LaunchWindowGuard(id: id, model: model))
            .onAppear {
                if model.hasWindowRequest(id) {
                    model.revealWindow(id)
                    return
                }
                let dismissWindow = dismissWindow
                Task { @MainActor in
                    // The user may have asked for the window in the meantime.
                    if model.hasWindowRequest(id) {
                        model.revealWindow(id)
                    } else {
                        dismissWindow(id: id)
                    }
                }
            }
            .onDisappear {
                // The window closed: the next unrequested appearance is suppressed again.
                _ = model.consumeWindowRequest(id)
            }
    }
}
