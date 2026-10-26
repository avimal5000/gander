import Foundation
import SwayModels

@testable import SwayUI

/// An `AppModel` wired to fakes for every collaborator, with a manual clock and no timers.
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
    let hotKeys: FakeHotKeys
    let loginItem: FakeLoginItem
    let system: FakeSystem
    let overlay: FakeOverlay
    let feedback: FakeFeedback
    let clock: TestClock
    let appState: FakeAppState
    let keyMonitor: FakeKeyMonitor
    /// Where `NSApplication` notifications are posted.
    let notifications: NotificationCenter
    /// Where `NSWorkspace` notifications are posted.
    let workspace: NotificationCenter
    let defaults: UserDefaults
    private let suiteName: String

    /// - Parameters:
    ///   - autoRun: when true the fake pose source reports `.starting` and `.running` on every start by itself.
    ///   - calibrated: seeds the calibration library with a profile for `layout` for each of `calibrationCameras`.
    ///   - capturePicks: the camera capture opens when none is selected (the system default with no built-in in
    ///     use); the fake pose source then runs it.
    ///   - appActive: whether Sway counts as the active app at launch.
    ///   - trackingSaved: seeds `sway.trackingEnabled` as if the user had left Tracking on.
    ///   - seed: writes anything else into the defaults before the model launches.
    static func make(
        authorization: CameraAuthorization = .authorized,
        layout: DisplayLayout = Fixtures.twoDisplays,
        autoRun: Bool = false,
        savedCameraID: String? = nil,
        analysis: GateAnalysis = Fixtures.analysis(),
        trusted: Bool = true,
        calibrated: Bool = false,
        calibrationCameras: [String?] = [Fixtures.builtInCamera.name],
        capturePicks: CameraDevice? = nil,
        trackingSaved: Bool = false,
        appActive: Bool = false,
        hotKeys: FakeHotKeys = FakeHotKeys(),
        suiteName: String = Harness.temporarySuiteName(),
        seed: (UserDefaults) -> Void = { _ in }
    ) -> Harness {
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("Cannot create test defaults") }
        if let savedCameraID { defaults.set(savedCameraID, forKey: DefaultsKey.cameraDeviceID) }
        if calibrated {
            let profiles = calibrationCameras.map { Fixtures.profile(layout: layout, cameraName: $0) }
            Harness.seedLibrary(profiles, into: defaults)
        }
        if trackingSaved { defaults.set(true, forKey: DefaultsKey.trackingEnabled) }
        seed(defaults)
        let camera = FakeFrameSource(
            authorization: authorization, devices: [Fixtures.builtInCamera, Fixtures.externalCamera],
            fallbackDevice: capturePicks
        )
        let pose = FakePoseSource(autoRunDevice: capturePicks ?? (autoRun ? Fixtures.builtInCamera : nil))
        let displays = FakeDisplayProvider(layout: layout)
        let store = FakeTraceStore()
        let analyzer = FakeAnalyzer(analysis: analysis)
        let engine = FakeSwitchEngine()
        let focus = FakeFocus(trusted: trusted)
        let loginItem = FakeLoginItem()
        let system = FakeSystem()
        let overlay = FakeOverlay()
        let feedback = FakeFeedback()
        let clock = TestClock()
        let appState = FakeAppState()
        let keyMonitor = FakeKeyMonitor()
        appState.isActive = appActive
        let notifications = NotificationCenter()
        let workspace = NotificationCenter()
        let environment = AppModelEnvironment(
            clock: clock.reading,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            system: system,
            overlay: overlay,
            feedback: feedback,
            reduceMotion: { [appState] in appState.reduceMotion },
            notificationCenter: notifications,
            workspaceNotificationCenter: workspace,
            isAppActive: { [appState] in appState.isActive },
            gateTickInterval: nil,
            focusTickInterval: nil,
            trackingTickInterval: nil,
            setupTickInterval: nil,
            keyMonitor: keyMonitor,
            cameraStartTimeout: 10
        )
        let model = AppModel(
            camera: camera, poseSource: pose, displays: displays, traceStore: store, analyzer: analyzer,
            engine: engine, focus: focus, hotKeys: hotKeys, loginItem: loginItem, defaults: defaults,
            environment: environment
        )
        return Harness(
            model: model, camera: camera, pose: pose, displays: displays, store: store, analyzer: analyzer,
            engine: engine, focus: focus, hotKeys: hotKeys, loginItem: loginItem, system: system, overlay: overlay,
            feedback: feedback, clock: clock, appState: appState, keyMonitor: keyMonitor, notifications: notifications,
            workspace: workspace, defaults: defaults, suiteName: suiteName
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

    /// Writes a calibration library holding `profiles` (newest first) into `defaults`.
    static func seedLibrary(_ profiles: [CalibrationProfile], into defaults: UserDefaults) {
        let library = CalibrationLibrary(profiles: profiles)
        guard let data = try? AppModel.encoder().encode(library) else { fatalError("Cannot encode the library") }
        defaults.set(data, forKey: DefaultsKey.calibrationLibrary)
    }

    /// The library as stored in the defaults, or `nil` when absent.
    func storedLibrary() -> CalibrationLibrary? {
        guard let data = defaults.data(forKey: DefaultsKey.calibrationLibrary) else { return nil }
        return try? AppModel.decoder().decode(CalibrationLibrary.self, from: data)
    }

    /// Builds a second model on the same defaults suite, as after a relaunch (optionally on another layout).
    func relaunchedModel(
        layout: DisplayLayout = Fixtures.twoDisplays, pose: FakePoseSource = FakePoseSource(),
        hotKeys: FakeHotKeys = FakeHotKeys()
    ) -> AppModel {
        let environment = AppModelEnvironment(
            clock: clock.reading, now: { Date() }, system: FakeSystem(), overlay: FakeOverlay(),
            feedback: FakeFeedback(), reduceMotion: { false },
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
            isAppActive: { false }, gateTickInterval: nil, focusTickInterval: nil, trackingTickInterval: nil,
            setupTickInterval: nil, keyMonitor: FakeKeyMonitor(), cameraStartTimeout: 10
        )
        return AppModel(
            camera: camera, poseSource: pose, displays: FakeDisplayProvider(layout: layout),
            traceStore: store, analyzer: analyzer, engine: engine, focus: focus, hotKeys: hotKeys,
            loginItem: FakeLoginItem(), defaults: defaults, environment: environment
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
