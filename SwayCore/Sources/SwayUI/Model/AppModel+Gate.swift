import Foundation
import SwayModels

// The guided gate test (SPEC F7, flow B). `GateTestSession` is the pure state machine; this extension feeds it
// samples and timer ticks, shows the overlays, and hands the finished trace to the analyzer.
extension AppModel {
    /// True when the layout has enough displays to run the test.
    var canRunGateTest: Bool { layout.displays.count >= GateTestSession.minimumDisplays }

    /// True when more displays are connected than v1 will track.
    var exceedsTrackedDisplays: Bool { layout.displays.count > SwayPolicy.maxTrackedDisplays }

    /// Starts the guided test: checks the displays, makes sure the camera runs, then begins the first step.
    func startGateTest() async {
        guard gateRunState == .idle else { return }
        gateMessage = nil
        let current = displays.currentLayout
        layout = current
        guard current.displays.count >= GateTestSession.minimumDisplays else {
            gateMessage = .error("The gate test needs at least 2 displays. Connect another display and try again.")
            return
        }
        if let missing = current.displays.first(where: { !environment.overlay.canPresent(on: $0) }) {
            gateMessage = .error("Sway could not find the screen for \(missing.name). Check the display connections.")
            return
        }

        gateRunState = .startingCamera
        gateCameraDeadline = environment.clock() + environment.cameraStartTimeout
        startGateTimer()
        await reconcileCamera().value
        guard gateRunState == .startingCamera else { return }
        if status.isRunning { beginGateSession() }
    }

    /// Aborts the test (Cancel button, Esc, closing the gate window). Removes the overlays and puts the camera
    /// back to what the live toggle says.
    func cancelGateTest(reason: String? = nil) {
        guard gateRunState != .idle else { return }
        gateSession?.cancel()
        endGate(message: reason.map(UserMessage.info))
        reconcileCamera()
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
            configuration: gateConfiguration,
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
                    "The camera stopped delivering frames (\(newStatus.summary.lowercased())). Run the test again.")
            }
        }
    }

    /// Finishes a completed session: builds the trace, analyzes it, shows the report, and saves in DEBUG builds.
    private func completeGate(_ session: GateTestSession) {
        let trace = session.makeTrace(createdAt: environment.now())
        endGate(message: nil)
        reconcileCamera()
        guard let trace else { return }
        let result = analyzer.analyze(trace, thresholds: .default)
        adopt(result, trace: trace, source: .gateTest)
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
        gateTimerTask?.cancel()
        gateTimerTask = nil
        gateSession = nil
        gateProgress = nil
        gateRunState = .idle
        environment.overlay.dismiss()
        if let message { gateMessage = message }
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
