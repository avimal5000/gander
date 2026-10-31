import Foundation
import GanderModels

// The guided gate run (SPEC F7, flow B, and the Setup window's calibration, F20). `GateTestSession` is the pure state
// machine; this extension feeds it samples and timer ticks, shows the overlays, and hands the finished trace to the
// analyzer (the gate test) or to the calibration fit (`GatePurpose.calibration`, see `AppModel+Setup`).
extension AppModel {
    /// True when the layout has enough displays to run the test.
    var canRunGateTest: Bool { layout.displays.count >= GateTestSession.minimumDisplays }

    /// True when more displays are connected than v1 will track.
    var exceedsTrackedDisplays: Bool { layout.displays.count > GanderPolicy.maxTrackedDisplays }

    /// True while the Head-Pose Gate Test (not a calibration) is starting or running.
    var isGateTestRunning: Bool { gateRunState != .idle && gatePurpose == .gateTest }

    /// Starts the guided test: checks the displays, makes sure the camera runs, then begins the first step.
    func startGateTest() async {
        await startGateRun(.gateTest)
    }

    /// Starts a gate run for `purpose`. A problem found before it begins is shown where the purpose shows messages
    /// (the gate window, or the Setup window's camera check) and nothing starts.
    func startGateRun(_ purpose: GatePurpose) async {
        guard gateRunState == .idle else { return }
        switch purpose {
        case .gateTest: gateMessage = nil
        case .calibration: setupMessage = nil
        }
        let current = displays.currentLayout
        layout = current
        guard current.displays.count >= GateTestSession.minimumDisplays else {
            post(
                .error(
                    purpose == .gateTest
                        ? "The gate test needs at least 2 displays. Connect another display and try again."
                        : SetupPresentation.needsSecondDisplay), for: purpose)
            return
        }
        if let missing = current.displays.first(where: { !environment.overlay.canPresent(on: $0) }) {
            post(
                .error("Gander could not find the screen for \(missing.name). Check the display connections."),
                for: purpose)
            return
        }

        gatePurpose = purpose
        if purpose == .calibration { mutateSetup { $0.startCalibration() } }
        gateRunState = .startingCamera
        // Tracking holds while the run steers the camera.
        resetTracking()
        syncTrackingActivity()
        gateCameraDeadline = environment.clock() + environment.cameraStartTimeout
        startGateTimer()
        await reconcileCamera().value
        guard gateRunState == .startingCamera else { return }
        if status.isRunning { beginGateSession() }
    }

    /// Shows `message` where `purpose` shows messages.
    private func post(_ message: UserMessage, for purpose: GatePurpose) {
        switch purpose {
        case .gateTest: gateMessage = message
        case .calibration: setupMessage = message
        }
    }

    /// Aborts the gate test (Cancel button, closing the gate window). Removes the overlays and puts the camera back
    /// to what the Tracking switch says. Does nothing while a calibration runs: that is the Setup window's.
    func cancelGateTest(reason: String? = nil) {
        guard gateRunState != .idle, gatePurpose == .gateTest else { return }
        gateSession?.cancel()
        endGate(message: reason.map(UserMessage.info))
        reconcileCamera()
    }

    /// Cancels the calibration (Cancel button, Esc, closing the Setup window): back to the camera check.
    func cancelCalibration(reason: String? = SetupPresentation.calibrationCancelled) {
        guard gateRunState != .idle, gatePurpose == .calibration else { return }
        gateSession?.cancel()
        endGate(message: reason.map(UserMessage.info))
        reconcileCamera()
    }

    /// Cancels whatever gate run is going, saying `reason` in the window that started it. With no reason given (Esc on
    /// an overlay) it uses the run's own wording.
    func cancelRunningGate(reason: String? = nil) {
        switch gatePurpose {
        case .gateTest: cancelGateTest(reason: reason ?? "Gate test cancelled.")
        case .calibration: cancelCalibration(reason: reason ?? SetupPresentation.calibrationCancelled)
        }
    }

    /// Ends the test with an error and restores the camera.
    func abortGate(_ text: String) {
        guard gateRunState != .idle else { return }
        gateSession?.cancel()
        endGate(message: .error(text))
        reconcileCamera()
    }

    /// Advances time-driven transitions. Called by the gate timer; tests call it after moving their clock.
    func gateTick() {
        switch gateRunState {
        case .idle:
            break
        case .startingCamera:
            if environment.clock() >= gateCameraDeadline {
                abortGate("The camera did not start in time. Check that no other app is using it, then try again.")
            }
        case .running:
            gateSession?.advance()
            refreshGateUI()
        }
    }

    // MARK: Session wiring

    func beginGateSession() {
        guard gateRunState == .startingCamera else { return }
        var session = GateTestSession(
            layout: layout,
            cameraName: currentCameraName,
            configuration: gatePurpose == .calibration ? .calibration : gateConfiguration,
            clock: environment.clock
        )
        session.start()
        gateSession = session
        gateRunState = .running
        isShowingReport = false
        refreshGateUI()
    }

    /// Reacts to a sample that was just offered to the session.
    func gateSessionDidIngest() {
        guard let session = gateSession else { return }
        if session.phase == .finished {
            completeGate(session)
            return
        }
        // Per-sample progress is not worth a UI update; only step or phase changes are.
        let progress = session.progress
        if progress?.stepNumber != gateProgress?.stepNumber || progress?.phase != gateProgress?.phase {
            refreshGateUI()
        }
    }

    /// Pushes the session's progress to the gate window and the overlay, or completes the test.
    func refreshGateUI() {
        guard let session = gateSession else { return }
        switch session.phase {
        case .finished:
            completeGate(session)
        case .settling, .holding:
            if let progress = session.progress {
                gateProgress = progress
                environment.overlay.present(progress)
            }
        case .pending, .cancelled:
            break
        }
    }

    /// Reacts to camera status changes while a test is starting or running.
    func reactToStatusDuringGate(_ newStatus: CaptureStatus) {
        switch gateRunState {
        case .idle:
            break
        case .startingCamera:
            if newStatus.isRunning {
                beginGateSession()
            } else if case .failed(let error) = newStatus {
                abortGate("The camera failed: \(error.userMessage).")
            }
        case .running:
            if !newStatus.isRunning {
                abortGate(
                    "The camera stopped delivering frames (\(newStatus.summary.lowercased())). "
                        + gatePurpose.tryAgain)
            }
        }
    }

    /// Finishes a completed session: builds the trace, analyzes it, shows the report, and saves in DEBUG builds. A
    /// calibration run goes to the Setup window's result instead.
    private func completeGate(_ session: GateTestSession) {
        let trace = session.makeTrace(createdAt: environment.now())
        if gatePurpose == .calibration {
            // The result step first, so ending the run does not send the window back to the camera check.
            mutateSetup { $0.calibrationFinished() }
            endGate(message: nil)
            reconcileCamera()
            if let trace { finishCalibration(from: trace) }
            return
        }
        endGate(message: nil)
        reconcileCamera()
        guard let trace else { return }
        let result = analyzer.analyze(trace, thresholds: .default)
        adopt(result, trace: trace, source: .gateTest)
        refitCalibration(from: trace)
        isShowingReport = true
        saveGateTrace(trace)
    }

    private func saveGateTrace(_ trace: PoseTrace) {
        #if DEBUG
        do {
            traceSaveStatus = .saved(try traceStore.save(trace))
        } catch {
            log.error("Saving the gate trace failed: \(String(describing: error), privacy: .public)")
            traceSaveStatus = .failed(userMessage(for: error))
        }
        #else
        traceSaveStatus = .disabledInRelease
        #endif
    }

    /// Resets all gate-run state and removes the overlays. Does not touch the camera, so it is safe inside the
    /// camera chain; callers outside the chain follow it with `reconcileCamera()`.
    func endGate(message: UserMessage?) {
        let purpose = gatePurpose
        gateTimerTask?.cancel()
        gateTimerTask = nil
        gateSession = nil
        gateProgress = nil
        gateRunState = .idle
        gatePurpose = .gateTest
        syncTrackingActivity()
        environment.overlay.dismiss()
        switch purpose {
        case .gateTest:
            if let message { gateMessage = message }
        case .calibration:
            // A run that ended early sends the Setup window back to the camera check.
            if let message { setupMessage = message }
            mutateSetup { $0.calibrationCancelled() }
        }
    }

    // MARK: Timer

    private func startGateTimer() {
        gateTimerTask?.cancel()
        guard let interval = environment.gateTickInterval else { return }
        gateTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.gateTick()
            }
        }
    }

    // MARK: Report navigation

    /// Returns the gate window to the setup form.
    func showGateSetup() {
        isShowingReport = false
        gateMessage = nil
    }
}
