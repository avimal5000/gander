import Foundation
import SwiftUI
import Testing

@testable import GanderUI

@MainActor
@Suite("First-run onboarding")
struct OnboardingTests {
    @Test func theRuleOpensOnlyForAnEmptyLibraryThatHasNotSeenIt() {
        #expect(AppModel.shouldAutoOpenOnboarding(libraryIsEmpty: true, seen: false))
        #expect(!AppModel.shouldAutoOpenOnboarding(libraryIsEmpty: true, seen: true))
        #expect(!AppModel.shouldAutoOpenOnboarding(libraryIsEmpty: false, seen: false))
        #expect(!AppModel.shouldAutoOpenOnboarding(libraryIsEmpty: false, seen: true))
    }

    @Test func aFirstLaunchRequestsTheSetupWindowAndMarksItSeenOnceItAppears() {
        let h = Harness.make()
        defer { h.tearDown() }
        #expect(!h.defaults.bool(forKey: DefaultsKey.onboardingSeen))

        #expect(h.model.requestOnboardingIfFirstRun())
        #expect(h.model.hasWindowRequest(GanderWindowID.setup))
        #expect(!h.defaults.bool(forKey: DefaultsKey.onboardingSeen), "Not seen until the window appears")

        #expect(h.model.setupWindowDidAppear(), "Reports the first-run opening")
        #expect(h.defaults.bool(forKey: DefaultsKey.onboardingSeen))
        #expect(h.model.setupFlow?.step == .welcome)

        h.model.setupWindowDidDisappear()
        let again = Harness.make(seed: { $0.set(true, forKey: DefaultsKey.onboardingSeen) })
        defer { again.tearDown() }
        #expect(!again.model.requestOnboardingIfFirstRun())
        #expect(!again.model.hasWindowRequest(GanderWindowID.setup))
    }

    @Test func aMenuOpeningIsNotTheFirstRunOpening() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(!h.defaults.bool(forKey: DefaultsKey.onboardingSeen))
    }

    @Test func calibrationsMeanNoAutoOpen() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        #expect(!h.model.requestOnboardingIfFirstRun())
        #expect(!h.model.hasWindowRequest(GanderWindowID.setup))
    }

    @Test func theMigrationCopiesNothingThatCountsAsOnboardingSeen() {
        let suite = "gander.test.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        EarlierNameMigration.run(in: defaults, earlierValues: ["sway.trackingEnabled": true])
        #expect(defaults.bool(forKey: "gander.trackingEnabled"))
        #expect(!defaults.bool(forKey: DefaultsKey.onboardingSeen))
    }

    @Test func theSceneTimelineMovesTheFocusAndKeepsALoop() {
        let start = IntroSceneState(at: 0)
        #expect(start.turn == 0 && start.ring == 0 && start.typedCount == 0)

        let arrived = IntroSceneState(at: IntroSceneState.stillTime)
        #expect(arrived.turn == 1 && arrived.ring == 1)
        #expect(arrived.typedCount == IntroSceneState.typedText.count)

        let middle = IntroSceneState(at: 3.5)
        #expect(middle.ring > 0 && middle.ring < 1)

        let wrapped = IntroSceneState(at: IntroSceneState.duration + 0.5)
        #expect(wrapped == IntroSceneState(at: 0.5))
        #expect(IntroSceneState(at: 9.9).ring == 0)
    }

    @Test func theIntroPagesRenderInLightAndDark() {
        let h = Harness.make()
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        for page in 0..<SetupFlow.introPageCount {
            for scheme in [ColorScheme.light, .dark] {
                let view = SetupView(model: h.model).environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                #expect(renderer.cgImage != nil, "Page \(page + 1), \(scheme)")
            }
            h.model.nextIntroPage()
        }
        #expect(h.model.setupFlow?.introPage == SetupFlow.introPageCount - 1)
    }

    @Test func theWelcomeTourOpensOnTheIntroEvenWhenCalibrated() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }

        h.model.requestWelcomeTour()
        h.openSetup(welcome: true)

        #expect(h.model.setupFlow?.step == .welcome)
        #expect(!h.model.tourPending)
    }

    @Test func theWelcomeTourRestartsAnOpenSetupWindow() {
        let h = Harness.make(calibrated: true)
        defer { h.tearDown() }
        h.openSetup(welcome: true)
        #expect(h.model.setupFlow?.step == .cameraCheck)

        h.model.requestWelcomeTour()

        #expect(h.model.setupFlow?.step == .welcome)
    }
}
