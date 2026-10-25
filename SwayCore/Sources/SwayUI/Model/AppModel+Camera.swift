import Foundation
import SwayModels

// Camera lifecycle. The pose source runs only while Tracking is on and a calibration fits, or a gate test is running;
// every start and stop goes through one serial chain of operations so rapid toggling can never leave the camera in a
// state that disagrees with the latest request.
extension AppModel {
    // MARK: User actions

    /// Chooses the camera, persists the choice (`nil` means default), and restarts capture if it is running. The
    /// calibration is looked up per camera, so the active calibration may change.
    func selectCamera(_ id: String?) async {
        guard id != selectedCameraID else { return }
        selectedCameraID = id
        if let id {
            defaults.set(id, forKey: DefaultsKey.cameraDeviceID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.cameraDeviceID)
        }
        refreshActiveCalibration()
        guard streamTask != nil else { return }
        await enqueueCameraWork { await $0.restartPoseSource() }.value
    }

    // MARK: Serial camera operations

    /// Appends `work` to the camera operation chain and returns its task.
    @discardableResult
    func enqueueCameraWork(_ work: @escaping @MainActor (AppModel) async -> Void) -> Task<Void, Never> {
        let previous = cameraOperation
        let operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
        cameraOperation = operation
        return operation
    }

    /// Queues a reconcile: start the camera if something wants it, stop it if nothing does.
    @discardableResult
    func reconcileCamera() -> Task<Void, Never> {
        enqueueCameraWork { await $0.performCameraReconcile() }
    }

    /// True when a gate test needs frames, or Tracking is on with a calibration that fits two or more displays.
    var wantsCamera: Bool {
        gateRunState != .idle || (trackingEnabled && activeCalibration != nil && layout.displays.count >= 2)
    }

    /// The configuration the pose source should run with right now. Landmarks cost a second Vision request per
    /// frame, so they are on exactly while a gate test needs the camera (including its camera-start phase) and
    /// off for Tracking (SPEC D15).
    var desiredConfiguration: PoseSourceConfiguration {
        PoseSourceConfiguration(cameraDeviceID: selectedCameraID, includeLandmarks: gateRunState != .idle)
    }

    func performCameraReconcile() async {
        if wantsCamera {
            if streamTask != nil {
                // A running stream is kept unless it was started with another configuration, for example Tracking
                // without landmarks when a gate test begins (or the gate test's stream once it has ended).
                if activeConfiguration != desiredConfiguration { await restartPoseSource() }
                return
            }
            let gateWanted = gateRunState != .idle
            if await startPoseSource() == false {
                cameraStartFailed(gateWanted: gateWanted)
            }
        } else if streamTask != nil {
            await stopPoseSource()
        }
    }

    func restartPoseSource() async {
        await stopPoseSource()
        guard wantsCamera else { return }
        let gateWanted = gateRunState != .idle
        if await startPoseSource() == false {
            cameraStartFailed(gateWanted: gateWanted)
        }
    }

    // MARK: Start and stop

    /// Starts the pose source and begins consuming its stream. Returns false, with the reason surfaced in
    /// `permissionPrompt` or `status`, when capture could not start.
    func startPoseSource() async -> Bool {
        authorization = camera.authorizationStatus()
        switch authorization {
        case .authorized:
            permissionPrompt = nil
        case .notDetermined:
            permissionPrompt = .explanation
            return false
        case .denied:
            permissionPrompt = .denied
            return false
        case .restricted:
            permissionPrompt = .restricted
            return false
        }

        status = .starting
        clearLiveReadings()
        statusDidChange()
        let configuration = desiredConfiguration
        do {
            let stream = try await poseSource.start(configuration)
            activeConfiguration = configuration
            rebuildDecider()
            beginConsuming(stream)
            return true
        } catch let error as CameraError {
            handleStartFailure(error)
        } catch {
            handleStartFailure(.configurationFailed(error.localizedDescription))
        }
        return false
    }

    private func handleStartFailure(_ error: CameraError) {
        log.error("Pose source failed to start: \(String(describing: error), privacy: .public)")
        if error == .notAuthorized {
            // The pose source disagrees with our cached permission; trust it and show the instructions.
            authorization = camera.authorizationStatus()
            permissionPrompt =
                authorization == .restricted ? .restricted : (authorization == .notDetermined ? .explanation : .denied)
            status = .stopped
        } else {
            status = .failed(error)
        }
        statusDidChange()
    }

    /// Stops the pose source and tears down the stream consumer. Keeps a `.failed` status visible.
    func stopPoseSource() async {
        let task = streamTask
        streamTask = nil
        activeConfiguration = nil
        task?.cancel()
        await poseSource.stop()
        if case .failed = status {
            // Leave the failure on screen until the next start.
        } else {
            status = .stopped
        }
        latestSample = nil
        liveClassification = nil
        liveGuessFeatureSet = nil
        history.reset()
        readout = LiveReadout()
        resetTracking()
        statusDidChange()
        #if DEBUG
        finishRecordingIfNeeded()
        #endif
    }

    /// The camera status changed: its device may change which calibration applies, and whether the focused display
    /// needs polling.
    func statusDidChange() {
        refreshActiveCalibration()
        syncTrackingActivity()
    }

    /// Resets intent state after a start attempt failed. Runs inside the camera chain, so it must not wait on it.
    ///
    /// The Tracking switch is turned off in memory (never in `UserDefaults`) except when the camera is blocked by its
    /// permission: then it stays on, so the status says "Camera access needed" and tracking resumes once access is
    /// granted. While the permission is still undecided, the explanation holds the request as a pending intent.
    private func cameraStartFailed(gateWanted: Bool) {
        switch permissionPrompt {
        case .explanation:
            pendingIntent = gateWanted ? .gateTest : .tracking
            trackingEnabled = false
        case .denied, .restricted:
            break
        case nil:
            trackingEnabled = false
        }
        if gateWanted {
            let text = permissionPrompt == nil ? gateStartFailureText() : nil
            endGate(message: text.map(UserMessage.error))
        }
    }

    private func gateStartFailureText() -> String {
        if case .failed(let error) = status {
            return "The camera could not start: \(error.userMessage)."
        }
        return "The camera could not start."
    }

    // MARK: Stream consumption

    private func beginConsuming(_ stream: AsyncStream<PoseSourceEvent>) {
        streamGeneration += 1
        let generation = streamGeneration
        streamTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handleStreamEvent(event, generation: generation)
            }
            self?.streamDidEnd(generation: generation)
        }
    }

    /// Applies an event from the stream consumed as `generation`, unless that stream was stopped or replaced.
    ///
    /// Cancelling the consumer does not stop delivery at once: the iterator's `next()` runs off the main actor, so a
    /// cancel that lands between two iterations leaves the stream open, and `AsyncStream` hands out what is buffered
    /// before it reports the end. That includes the `.stopped` a pose source yields from `stop()`, which would
    /// otherwise replace a `.failed` status, or reach a newer run after a restart (clearing its readings or aborting a
    /// running gate test).
    func handleStreamEvent(_ event: PoseSourceEvent, generation: Int) {
        guard generation == streamGeneration, streamTask != nil else { return }
        handle(event)
    }

    /// The stream finished without us asking: capture is over.
    private func streamDidEnd(generation: Int) {
        guard generation == streamGeneration, streamTask != nil else { return }
        streamTask = nil
        activeConfiguration = nil
        if status.isRunning || status == .starting { status = .stopped }
        clearLiveReadings()
        trackingEnabled = false
        statusDidChange()
        if gateRunState != .idle {
            abortGate("The camera stopped unexpectedly. Run the test again.")
        }
    }

    /// Applies one pose source event.
    func handle(_ event: PoseSourceEvent) {
        switch event {
        case .sample(let sample):
            handleSample(sample)
        case .status(let newStatus):
            handleStatus(newStatus)
        }
    }

    private func handleSample(_ sample: PoseSample) {
        latestSample = sample
        let face = sample.pose != nil
        if face != hasFace { hasFace = face }
        history.append(sample)
        if readout.isDue(for: sample) { readout = LiveReadout(sample: sample, fps: history.fps) }
        updateLiveClassification(for: sample.pose)
        processTracking(sample)
        #if DEBUG
        recorder.append(sample)
        #endif
        if gateSession != nil {
            gateSession?.ingest(sample)
            gateSessionDidIngest()
        }
    }

    /// Forgets the latest pose, the plot history, the live guess, and the tracking loop's dwell and focus (camera
    /// stopped, restarted, or interrupted).
    private func clearLiveReadings() {
        latestSample = nil
        if hasFace { hasFace = false }
        liveClassification = nil
        liveGuessFeatureSet = nil
        history.reset()
        readout = LiveReadout()
        resetTracking()
    }

    private func handleStatus(_ newStatus: CaptureStatus) {
        status = newStatus
        if case .running(let device) = newStatus {
            if let device { runningCameraName = device.name }
        } else {
            clearLiveReadings()
        }
        statusDidChange()
        reactToStatusDuringGate(newStatus)
        if case .failed = newStatus {
            // An automatic turn-off: the saved choice stays, so the next launch tries again.
            trackingEnabled = false
            statusDidChange()
            reconcileCamera()
        }
    }
}
