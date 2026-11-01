import SwiftUI

/// The welcome step (SPEC F26, D40): on first setup, a four page intro before any permission is asked for: what Gander
/// does, how it works, the privacy promise, and where to find it. `SetupFlow` holds the page; this view draws it.
struct SetupWelcomeStep: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: Int { model.setupFlow?.introPage ?? 0 }
    private var isLast: Bool { model.setupFlow?.isLastIntroPage ?? false }

    var body: some View {
        VStack(spacing: 0) {
            pageView
                .id(page)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            navigation
        }
        .animation(SetupView.stepAnimation(reduceMotion: reduceMotion), value: page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
        case 0: SetupIntroWelcomePage()
        case 1: SetupIntroStepsPage()
        case 2: SetupIntroPrivacyPage()
        default: SetupIntroMenuBarPage()
        }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button(SetupPresentation.skipButton) { model.getStartedFromSetup() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
                .accessibilityHidden(isLast)
            Spacer()
            Button(SetupPresentation.backButton) { model.previousIntroPage() }
                .opacity(page == 0 ? 0 : 1)
                .disabled(page == 0)
                .accessibilityHidden(page == 0)
            Button(isLast ? SetupPresentation.welcomeButton : SetupPresentation.nextButton) {
                if isLast { model.getStartedFromSetup() } else { model.nextIntroPage() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .overlay { dots }
    }

    /// The page dots, one element for VoiceOver ("Page 2 of 4").
    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<SetupFlow.introPageCount, id: \.self) { index in
                Circle()
                    .fill(
                        index == page
                            ? GanderPalette.accent(for: colorScheme) : IntroStyle.ink(colorScheme).opacity(0.22)
                    )
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SetupPresentation.pageLabel(page))
    }
}
