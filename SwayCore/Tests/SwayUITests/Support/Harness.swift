import Foundation
import SwayModels

@testable import SwayUI

/// An `AppModel` wired to fakes for every collaborator, with a manual clock and no gate timer.
@MainActor
struct Harness {
    let model: AppModel
    let camera: FakeFrameSource
    let pose: FakePoseSource
    let displays: FakeDisplayProvider
    let store: FakeTraceStore
    let analyzer: FakeAnalyzer
    let engine: FakeSwitchEngine
    let focus: FakeFocus
    let system: FakeSystem
    let overlay: FakeOverlay
    let clock: TestClock
    let notifications: NotificationCenter
    let defaults: UserDefaults
    private let suiteName: String

    /// - Parameters:
    ///   - autoRun: when true the fake pose source reports `.starting` and `.running` on every start by itself.
    static func make(
        authorization: CameraAuthorization = .authorized,
        layout: DisplayLayout = Fixtures.twoDisplays,
        autoRun: Bool = false,
        savedCameraID: String? = nil,
        analysis: GateAnalysis = Fixtures.analysis(),
        trusted: Bool = true,
        suiteName: String = Harness.temporarySuiteName()
    ) -> Harness {
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("Cannot create test defaults") }
        if let savedCameraID { defaults.set(savedCameraID, forKey: DefaultsKey.cameraDeviceID) }
        let camera = FakeFrameSource(
            authorization: authorization, devices: [Fixtures.builtInCamera, Fixtures.externalCamera]
        )
        let pose = FakePoseSource(autoRunDevice: autoRun ? Fixtures.builtInCamera : nil)
        let displays = FakeDisplayProvider(layout: layout)
        let store = FakeTraceStore()
        let analyzer = FakeAnalyzer(analysis: analysis)
        let engine = FakeSwitchEngine()
        let focus = FakeFocus(trusted: trusted)
        let system = FakeSystem()
        let overlay = FakeOverlay()
        let clock = TestClock()
        let notifications = NotificationCenter()
        let environment = AppModelEnvironment(
            clock: clock.reading,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            system: system,
            overlay: overlay,
            notificationCenter: notifications,
            gateTickInterval: nil,
            focusTickInterval: nil,
            cameraStartTimeout: 10
        )
        let model = AppModel(
            camera: camera, poseSource: pose, displays: displays, traceStore: store, analyzer: analyzer,
            engine: engine, focus: focus, defaults: defaults, environment: environment
        )
        return Harness(
            model: model, camera: camera, pose: pose, displays: displays, store: store, analyzer: analyzer,
            engine: engine, focus: focus, system: system, overlay: overlay, clock: clock,
            notifications: notifications, defaults: defaults, suiteName: suiteName
        )
    }

    /// Removes the temporary defaults suite and its file.
    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }

    /// A fresh defaults suite stored under the temporary directory (CONTRACT section 12). An absolute path as the
    /// suite name makes the preferences system keep the suite in `<path>.plist`; a plain name would leave a file in
    /// `~/Library/Preferences` for every test run.
    static func temporarySuiteName() -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sway-ui-tests-defaults")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).path
    }

    /// Builds a second model on the same defaults suite, as after a relaunch (optionally on another layout).
    func relaunchedModel(layout: DisplayLayout = Fixtures.twoDisplays) -> AppModel {
        let environment = AppModelEnvironment(
            clock: clock.reading, now: { Date() }, system: FakeSystem(), overlay: FakeOverlay(),
            notificationCenter: NotificationCenter(), gateTickInterval: nil, focusTickInterval: nil,
            cameraStartTimeout: 10
        )
        return AppModel(
            camera: camera, poseSource: FakePoseSource(), displays: FakeDisplayProvider(layout: layout),
            traceStore: store, analyzer: analyzer, engine: engine, focus: focus, defaults: defaults,
            environment: environment
        )
    }

    // MARK: Driving samples

    /// Offers one sample stamped with the clock's current time.
    func feed(face: Bool = true, yaw: Double = 0, pitch: Double = 0) {
        model.handle(.sample(Fixtures.sample(at: clock.now, face: face, yaw: yaw, pitch: pitch)))
    }

    /// Advances the clock by `dt` and offers a sample, `frames` times.
    func run(frames: Int, dt: TimeInterval = 0.25, face: Bool = true, yaw: Double = 0) {
        for _ in 0..<frames {
            clock.advance(by: dt)
            feed(face: face, yaw: yaw)
        }
    }

    /// Reports the camera as running, as the live pose source would.
    func reportRunning() {
        model.handle(.status(.running(Fixtures.builtInCamera)))
    }
}

/// Polls `condition` (yielding to other main-actor work) until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
