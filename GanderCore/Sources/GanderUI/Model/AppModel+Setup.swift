import Foundation
import GanderModels

// The Set Up Gander window (SPEC F20, D30, CONTRACT 6.5.3). `SetupFlow` is the pure state machine that decides the step;
// this extension feeds it the facts (permissions, the calibration run), keeps the camera and the tracking hold in step
// with it, and turns a finished calibration run into a saved calibration and a verdict. The run itself is the gate
// machinery with `GatePurpose.calibration` (`AppModel+Gate`).
extension AppModel {
    /// Seconds between camera check hint refreshes: at most five per second.
    static let framingRefreshInterval: TimeInterval = 0.2

    // MARK: Derived state

    /// What the permission steps depend on.
    var setupFacts: SetupFlow.Facts {
        SetupFlow.Facts(
            cameraAuthorized: authorization == .authorized,
            accessibilityTrusted: isAccessibilityTrusted,
            accessibilitySkipped: setupAccessibilitySkipped
        )
    }

    /// The Setup window is on a step that needs the camera: the camera check or the calibration.
    var isSetupUsingCamera: Bool { setupFlow?.needsCamera ?? false }

    /// Automatic switching holds: the Setup window is on the camera check, the calibration, or the result.
    var isSetupHoldingTracking: Bool { setupFlow?.holdsTracking ?? false }

    /// True when the layout has enough displays to calibrate.
    var canStartCalibration: Bool { layout.displays.count >= GateTestSession.minimumDisplays }

    // MARK: Window lifecycle

    /// The Setup window appeared: open the flow at the first step that applies, after the welcome step when nothing is
    /// calibrated yet (SPEC F26). Ignored for the copy SwiftUI opens at launch, which the launch guard closes unseen
    /// (nobody asked for it), and when the flow is already open.
    func setupWindowDidAppear() {
        guard hasWindowRequest(GanderWindowID.setup), setupFlow == nil else { return }
        refreshEnvironment()
        refreshAccessibilityTrust()
        setupMessage = nil
        setupResult = nil
        let flow = SetupFlow(facts: setupFacts, showsWelcome: library.profiles.isEmpty)
        setupFlow = flow
        setupFlowDidChange(from: nil, to: flow)
    }

    /// The Setup window closed.
    func setupWindowDidDisappear() {
        closeSetup()
    }

    /// Closes the flow: cancels a calibration in progress, releases the tracking hold, and lets the camera go unless
    /// Tracking needs it. Safe to call when the window is not open.
    func closeSetup() {
        guard let old = setupFlow else { return }
        if gateRunState != .idle, gatePurpose == .calibration {
            gateSession?.cancel()
            endGate(message: nil)
        }
        setupFlow = nil
        setupMessage = nil
        setupResult = nil
        setupFlowDidChange(from: old, to: nil)
    }

    // MARK: Welcome

    /// "Get Started" on the welcome step: on to the first step that applies. The permissions are read again first,
    /// because the user may have read the welcome for a while.
    func getStartedFromSetup() {
        guard setupFlow?.step == .welcome else { return }
        refreshEnvironment()
        refreshAccessibilityTrust()
        let facts = setupFacts
        mutateSetup { $0.getStarted(facts) }
    }

    // MARK: Permission steps

    /// "Continue" on the camera step: shows the system's camera prompt, then moves on if access was granted.
    func requestCameraAccessFromSetup() async {
        guard setupFlow?.step == .cameraAccess else { return }
        if authorization == .notDetermined {
            authorization = await camera.requestAuthorization()
        } else {
            authorization = camera.authorizationStatus()
        }
        if authorization == .authorized, permissionPrompt == .explanation {
            // The menu asked the same question when the Tracking switch was turned on first; it is answered now, and
            // that switch's intent carries on.
            permissionPrompt = nil
            let intent = pendingIntent
            pendingIntent = nil
            if intent == .tracking { await setTrackingEnabled(true) }
        }
        updateSetupFlow()
    }

    /// "Skip for now" on the Accessibility step: the window moves on and does not ask again during this app run.
    func skipSetupAccessibility() {
        setupAccessibilitySkipped = true
        updateSetupFlow()
    }

    /// Re-applies the facts to the flow, moving it on (or back) when a permission changed.
    func updateSetupFlow() {
        let facts = setupFacts
        mutateSetup { $0.update(facts) }
    }

    /// Re-reads the permissions the Setup window waits for. The timer calls this once a second while a permission
    /// step shows; tests call it directly.
    func setupTick() {
        guard setupFlow?.isPermissionStep == true else { return }
        if camera.authorizationStatus() != authorization { refreshEnvironment() }
        refreshAccessibilityTrust()
        updateSetupFlow()
    }

    // MARK: Camera check

    /// Tries to start the camera again after it failed, for example with another camera chosen.
    func retrySetupCamera() {
        guard isSetupUsingCamera, streamTask == nil else { return }
        reconcileCamera()
    }

    /// Offers a pose sample to the camera check hint, at most `framingRefreshInterval` apart in sample time and only
    /// while the check shows. Assigned only when the advice changes.
    func updateFramingAdvice(for sample: PoseSample) {
        guard setupFlow?.step == .cameraCheck else { return }
        if let last = lastFramingRefresh, sample.timestamp >= last,
            sample.timestamp - last < Self.framingRefreshInterval
        {
            return
        }
        lastFramingRefresh = sample.timestamp
        let advice = FramingAdvice(sample.pose)
        if advice != framingAdvice { framingAdvice = advice }
    }

    /// Forgets the hint (the camera stopped, or the check begins again).
    func resetFramingAdvice() {
        lastFramingRefresh = nil
        if framingAdvice != .noFace { framingAdvice = .noFace }
    }

    // MARK: Calibration

    /// "Start calibration": runs the guided calibration over the displays. Needs the camera check step.
    func startCalibration() async {
        guard setupFlow?.step == .cameraCheck, gateRunState == .idle else { return }
        await startGateRun(.calibration)
    }

    /// "Calibrate again" on the result: back to the camera check.
    func calibrateAgain() {
        setupResult = nil
        setupMessage = nil
        mutateSetup { $0.calibrateAgain() }
    }

    /// "Start tracking" on the result: the user's own choice, so it is saved, and the window is done. The caller closes
    /// the window.
    func startTrackingFromSetup() async {
        // Tracking first, so the camera that is about to start for it is not stopped and started again.
        await setTrackingEnabled(true)
        closeSetup()
    }

    /// A calibration run completed: fit and save the profile, then say how well it separates the displays. A failed fit
    /// saves nothing, and neither does a fit that left out a display: the fitter drops a display it saw the face on too
    /// rarely, and a calibration without one of the connected displays could never be used for them. The gate window's
    /// report is untouched.
    func finishCalibration(from trace: PoseTrace) {
        let traced = trace.layout ?? layout
        let names = DisplayLabeler.labels(for: traced)
        let name = { (id: DisplayID) in names[id] ?? self.displayName(for: id) }
        switch fit(trace) {
        case .failure(let failure):
            setupResult = .failed(failure.text)
        case .success(let profile):
            let missing = traced.displays.map(\.id).filter { !profile.displayIDs.contains($0) }
            if !missing.isEmpty {
                setupResult = .missingDisplays(missing.map(name))
            } else {
                saveToLibrary(profile)
                setupResult = SetupResult(analysis: analyzer.analyze(trace, thresholds: .default), name: name)
            }
        }
        saveCalibrationTrace(trace)
    }

    private func saveCalibrationTrace(_ trace: PoseTrace) {
        #if DEBUG
        do {
            _ = try traceStore.save(trace)
        } catch {
            log.error("Saving the calibration trace failed: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    // MARK: Keeping the rest in step

    /// Applies `change` to the open flow. Does nothing when the window is closed or the flow does not change.
    func mutateSetup(_ change: (inout SetupFlow) -> Void) {
        guard let old = setupFlow else { return }
        var flow = old
        change(&flow)
        guard flow != old else { return }
        setupFlow = flow
        setupFlowDidChange(from: old, to: flow)
    }

    /// The flow moved (or opened or closed): sync the hold, the camera, the hint, and the permission timer.
    private func setupFlowDidChange(from old: SetupFlow?, to new: SetupFlow?) {
        let holdChanged = (old?.holdsTracking ?? false) != (new?.holdsTracking ?? false)
        let cameraChanged = (old?.needsCamera ?? false) != (new?.needsCamera ?? false)
        if new?.step == .cameraCheck, old?.step != .cameraCheck { resetFramingAdvice() }
        if new == nil { resetFramingAdvice() }
        if holdChanged { resetTracking() }
        syncTrackingActivity()
        syncSetupTimer()
        if cameraChanged { reconcileCamera() }
    }

    /// Runs the permission timer exactly while a permission step shows.
    private func syncSetupTimer() {
        guard setupFlow?.isPermissionStep == true else {
            setupTickTask?.cancel()
            setupTickTask = nil
            return
        }
        guard setupTickTask == nil, let interval = environment.setupTickInterval else { return }
        setupTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.setupTick()
            }
        }
    }
}
