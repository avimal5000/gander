import AVFoundation
import AppKit
import CoreMedia
import SwayModels
import os

/// Owns the `AVCaptureSession` and everything that decides when it runs: suspend/resume, disconnects,
/// stalls, and runtime errors. The decisions come from the pure types (`SuspendTracker`, `FrameWatchdog`,
/// `RuntimeRetryPolicy`, ...); this class applies them to AVFoundation.
///
/// Status sequence: `.starting` then `.running(device)`. While capture is wanted but not possible it reports
/// `.suspended`, `.interrupted`, or finally `.failed`, and `.stopped` after `stop()`.
///
/// Suspension is sticky (SPEC D43): the sleep, lock, and user-session observers are installed when the controller
/// is created and removed only when it is deallocated, so reasons are tracked whether or not capture is running.
/// `start` never builds a session while any reason is active.
final class CaptureSessionController: @unchecked Sendable {
    // @unchecked Sendable: every mutable property below is confined to `queue` (a private serial queue).
    // Public entry points hop onto `queue`, notification handlers hop onto `queue`, and timers fire on
    // `queue`. The only state shared with another thread is `watchdog`, an unfair lock, and the receiver's
    // own locks. AVFoundation objects never leave `queue`. `init` and `deinit` touch the queue-confined state
    // directly, which is safe because no other thread can hold a reference to the controller then.

    private static let log = SwayLog.logger(category: "camera")

    private let environment: CaptureEnvironment
    private let queue = DispatchQueue(label: "\(SwayPolicy.bundleIdentifier).camera.session")
    private let frameQueue = DispatchQueue(label: "\(SwayPolicy.bundleIdentifier).camera.frames")
    private let watchdog = OSAllocatedUnfairLock(initialState: FrameWatchdog())

    // MARK: State confined to `queue`

    private struct Configuration {
        let preferredID: String?
        let frameRate: Double
        let frameHandler: @Sendable (CameraFrame) -> Void
        let statusHandler: @Sendable (CaptureStatus) -> Void
    }

    private struct LiveSession {
        let generation: Int
        let avSession: AVCaptureSession
        let avDevice: AVCaptureDevice
        let input: AVCaptureDeviceInput
        let output: AVCaptureVideoDataOutput
        let receiver: FrameSampleReceiver
        let observers: [any NSObjectProtocol]
    }

    private struct ObserverToken {
        let center: NotificationCenter
        let token: any NSObjectProtocol
    }

    /// Present from `start` until `stop` (or a fatal failure). Holds the caller's handlers.
    private var configuration: Configuration?
    /// The device capture is bound to. Set at `start`; later rebuilds use the same device.
    private var activeDevice: CameraDevice?
    /// The live AVFoundation session; `nil` while suspended, interrupted without a session, or stopped.
    private var live: LiveSession?
    private var suspend = SuspendTracker()
    private var retryPolicy = RuntimeRetryPolicy()
    private var backoff = RetryBackoff()
    /// Set while the active device is missing; cleared when it reconnects and the session is rebuilt.
    private var awaitingReconnectID: String?
    private var systemObservers: [ObserverToken] = []
    private var watchdogTimer: (any DispatchSourceTimer)?
    private var retryToken = 0
    private var generationCounter = 0
    private var lastStatus: CaptureStatus?

    /// Starts watching the system for suspend conditions right away (they are tracked from now on, even before
    /// `start`), and seeds `.displaysAsleep` if the main display is already asleep.
    init(environment: CaptureEnvironment = .live) {
        self.environment = environment
        if environment.isMainDisplayAsleep() {
            _ = suspend.begin(.displaysAsleep)
        }
        installSystemObservers()
    }

    deinit {
        removeSystemObservers()
    }

    // MARK: Entry points (any thread)

    func start(
        preferredID: String?,
        frameRate: Double,
        frameHandler: @escaping @Sendable (CameraFrame) -> Void,
        statusHandler: @escaping @Sendable (CaptureStatus) -> Void
    ) async throws {
        let configuration = Configuration(
            preferredID: preferredID,
            frameRate: frameRate,
            frameHandler: frameHandler,
            statusHandler: statusHandler
        )
        try await onQueue { try self.startOnQueue(configuration) }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.shutdown(finalStatus: self.configuration == nil ? nil : .stopped)
                continuation.resume()
            }
        }
    }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result(catching: work))
            }
        }
    }

    // MARK: Start

    private func startOnQueue(_ newConfiguration: Configuration) throws {
        guard environment.authorizationStatus() == .authorized else {
            throw CameraError.notAuthorized
        }
        let choice = try CameraDeviceSelector.select(
            preferredID: newConfiguration.preferredID,
            devices: environment.connectedDevices(),
            systemDefault: environment.systemDefaultDevice()
        )
        if choice.preferredWasUnavailable {
            Self.log.info("Preferred camera is not connected; using the \(String(describing: choice.reason)) camera")
        }

        // Restart: the previous session ends and its owner is told. Reasons already active stay active, and a
        // reason that began while capture was stopped counts too (D43).
        cancelRetry()
        teardownSession()
        watchdog.withLock { $0.disarm() }
        if configuration != nil { emit(.stopped) }

        configuration = newConfiguration
        activeDevice = choice.device
        awaitingReconnectID = nil
        lastStatus = nil
        retryPolicy.reset()
        backoff = RetryBackoff()

        switch suspend.captureRequested() {
        case .suspend(let reason):
            emit(.suspended(reason))
        case .resume:
            emit(.starting)
            do {
                try buildSession(for: choice.device, configuration: newConfiguration)
            } catch {
                shutdown(finalStatus: .failed(error))
                throw error
            }
        case .none, .reasonChanged:
            break
        }
    }

    // MARK: Session build and teardown

    /// Builds the session, starts it, applies the frame rate, and reports `.running`. On failure nothing is
    /// left running.
    private func buildSession(for device: CameraDevice, configuration: Configuration) throws(CameraError) {
        environment.turnCenterStageOff()
        guard let avDevice = AVCaptureDevice(uniqueID: device.id) else {
            throw .deviceUnavailable("\(device.name) is not available")
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: avDevice)
        } catch {
            throw .deviceUnavailable("Could not open \(device.name): \(error.localizedDescription)")
        }

        generationCounter += 1
        let generation = generationCounter
        let (output, receiver) = makeOutput(configuration: configuration, generation: generation)

        let avSession = AVCaptureSession()
        do {
            try configure(avSession, input: input, output: output, device: avDevice)
        } catch {
            output.setSampleBufferDelegate(nil, queue: nil)
            throw error
        }

        live = LiveSession(
            generation: generation,
            avSession: avSession,
            avDevice: avDevice,
            input: input,
            output: output,
            receiver: receiver,
            observers: sessionObservers(for: avSession, generation: generation)
        )

        avSession.startRunning()
        guard avSession.isRunning else {
            teardownSession()
            throw .deviceUnavailable("\(device.name) did not start")
        }
        applyFrameRate(configuration.frameRate, to: avDevice)

        awaitingReconnectID = nil
        let now = ProcessInfo.processInfo.systemUptime
        let stillStalled = watchdog.withLock { watchdog -> Bool in
            watchdog.arm(at: now)
            return watchdog.isStalled
        }
        startWatchdogTimer()
        // After a stall the status stays `.interrupted` until a frame arrives (see `framesResumed`).
        if !stillStalled { emit(.running(device)) }
    }

    /// The video-data output (late frames dropped, full-range 4:2:0) and its delegate, which delivers frames to the
    /// caller's frame handler on the private frame queue and reports the first frame of session `generation`.
    private func makeOutput(
        configuration: Configuration,
        generation: Int
    ) -> (output: AVCaptureVideoDataOutput, receiver: FrameSampleReceiver) {
        let receiver = FrameSampleReceiver(frameHandler: configuration.frameHandler, watchdog: watchdog) {
            [weak self] in
            guard let self else { return }
            self.queue.async { self.framesResumed(generation: generation) }
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(receiver, queue: frameQueue)
        return (output, receiver)
    }

    /// Adds the input and output and picks the format, inside one configuration transaction.
    private func configure(
        _ avSession: AVCaptureSession,
        input: AVCaptureDeviceInput,
        output: AVCaptureVideoDataOutput,
        device: AVCaptureDevice
    ) throws(CameraError) {
        avSession.beginConfiguration()
        defer { avSession.commitConfiguration() }

        guard avSession.canAddInput(input) else {
            throw .configurationFailed("The camera input cannot be added to the capture session")
        }
        avSession.addInput(input)
        selectFormat(on: avSession, device: device)
        guard avSession.canAddOutput(output) else {
            throw .configurationFailed("The video output cannot be added to the capture session")
        }
        avSession.addOutput(output)
    }

    /// 640x480 preset if supported, else the smallest format at least 640 wide, else the device default.
    private func selectFormat(on avSession: AVCaptureSession, device: AVCaptureDevice) {
        if avSession.canSetSessionPreset(.vga640x480) {
            avSession.sessionPreset = .vga640x480
            return
        }
        let formats = device.formats
        let sizes = formats.map { format -> VideoDimensions in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return VideoDimensions(width: Int(dimensions.width), height: Int(dimensions.height))
        }
        guard let index = CaptureFormatChooser.smallestSufficientIndex(among: sizes) else {
            Self.log.info("No format at least \(SwayPolicy.captureWidth) wide; keeping the device default")
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // Setting the active format makes the session leave preset control (input priority).
            device.activeFormat = formats[index]
        } catch {
            Self.log.error("Could not set the capture format: \(error.localizedDescription)")
        }
    }

    /// Locks the device and sets min and max frame duration to `1 / frameRate`, clamped into a supported
    /// range. Applied after the session is running so the preset cannot reset it. A failure is logged and
    /// capture continues at the device's own rate.
    private func applyFrameRate(_ requested: Double, to device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        let plainRanges = ranges.map { FrameRateRange(min: $0.minFrameRate, max: $0.maxFrameRate) }
        guard let rate = FrameRateClamper.clampedFrameRate(requested: requested, ranges: plainRanges) else {
            Self.log.info("The camera reports no frame rate ranges; keeping its own rate")
            return
        }
        let duration = Self.frameDuration(forRate: rate, ranges: ranges)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            Self.log.info("Frame rate set to \(rate) fps")
        } catch {
            Self.log.error("Could not set the frame rate: \(error.localizedDescription)")
        }
    }

    /// Uses the device's own boundary duration when the rate is a range limit, so AVFoundation never sees a
    /// duration just outside the range (it raises an exception for those).
    private static func frameDuration(forRate rate: Double, ranges: [AVFrameRateRange]) -> CMTime {
        let tolerance = FrameRateClamper.tolerance
        if let range = ranges.first(where: { abs($0.maxFrameRate - rate) <= tolerance }) {
            return range.minFrameDuration
        }
        if let range = ranges.first(where: { abs($0.minFrameRate - rate) <= tolerance }) {
            return range.maxFrameDuration
        }
        return FrameRateClamper.frameDuration(forRate: rate)
    }

    /// Stops and dismantles the live session so the camera light goes off. Idempotent.
    ///
    /// Order matters for privacy: the receiver is disabled first (no frame reaches the handler after this),
    /// then the session stops, then inputs and outputs are removed, and finally the frame queue is drained so
    /// that no handler call is still running when this returns.
    private func teardownSession() {
        stopWatchdogTimer()
        guard let session = live else { return }
        live = nil
        session.receiver.disable()
        session.output.setSampleBufferDelegate(nil, queue: nil)
        session.avSession.stopRunning()
        session.avSession.beginConfiguration()
        session.avSession.removeOutput(session.output)
        session.avSession.removeInput(session.input)
        session.avSession.commitConfiguration()
        for observer in session.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        frameQueue.sync {}
    }

    /// Ends the run: tears down, reports `finalStatus` (if any), and drops the handlers.
    ///
    /// Suspend reasons and the system observers stay (D43): the Mac may still be asleep or locked when the next
    /// `start` arrives, and that start must not turn the camera on.
    private func shutdown(finalStatus: CaptureStatus?) {
        cancelRetry()
        teardownSession()
        watchdog.withLock { $0.disarm() }
        if let finalStatus { emit(finalStatus) }
        suspend.captureStopped()
        retryPolicy.reset()
        backoff = RetryBackoff()
        configuration = nil
        activeDevice = nil
        awaitingReconnectID = nil
        lastStatus = nil
    }

    /// Capture failed and stopped (`.failed`); a later `start` begins fresh.
    private func fail(_ error: CameraError) {
        Self.log.error("Capture failed: \(String(describing: error))")
        shutdown(finalStatus: .failed(error))
    }

    // MARK: Rebuild (resume, reconnect, retry)

    /// Rebuilds the session for the active device after a suspension, reconnect, runtime error, or stall.
    ///
    /// A missing or unavailable device leaves the service `.interrupted` and schedules another attempt; any
    /// other failure is fatal.
    private func rebuild(announceStarting: Bool) {
        cancelRetry()
        guard let configuration, let target = activeDevice, !suspend.isSuspended else { return }
        teardownSession()
        guard environment.authorizationStatus() == .authorized else {
            fail(.notAuthorized)
            return
        }
        if announceStarting { emit(.starting) }
        do {
            try buildSession(for: target, configuration: configuration)
        } catch .deviceUnavailable(let message) {
            Self.log.info("Camera unavailable while rebuilding: \(message)")
            let connected = environment.isDeviceConnected(target.id)
            awaitingReconnectID = connected ? nil : target.id
            emit(.interrupted(connected ? message : Self.disconnectedMessage))
            scheduleRetry()
        } catch {
            fail(error)
        }
    }

    private static let disconnectedMessage = "Camera disconnected"

    /// Schedules another rebuild after a failure to find or open the device, waiting longer after each failure
    /// (1 s, 2 s, 5 s, then 10 s) until frames flow again.
    private func scheduleRetry() {
        retryToken &+= 1
        let token = retryToken
        let delay = backoff.nextOpenFailureDelay()
        Self.log.info("Trying the camera again in \(delay) s")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.retryToken == token else { return }
            self.rebuild(announceStarting: false)
        }
    }

    private func cancelRetry() {
        retryToken &+= 1
    }

    // MARK: Status

    private func emit(_ status: CaptureStatus) {
        guard let handler = configuration?.statusHandler, status != lastStatus else { return }
        lastStatus = status
        Self.log.info("Status: \(String(describing: status))")
        handler(status)
    }

    // MARK: Frame watchdog

    private func startWatchdogTimer() {
        stopWatchdogTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdogTimer() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard live != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch watchdog.withLock({ $0.check(at: now) }) {
        case .stalled:
            let reason = stallReason(default: "No frames received from the camera")
            Self.log.info("Camera stalled: \(reason)")
            beginStallWait()
            emit(.interrupted(reason))
        case .retryDue:
            Self.log.info("Camera still stalled; restarting the capture session")
            beginStallWait()
            rebuild(announceStarting: false)
        case .resumed, .none:
            break
        }
    }

    /// A stall began or a rebuild did not help: the watchdog waits longer (10 s, 30 s, then 60 s) before the next
    /// rebuild, so a camera held by another app is not hammered.
    private func beginStallWait() {
        let delay = backoff.nextStallRebuildDelay()
        watchdog.withLock { $0.setRetryInterval(delay) }
    }

    private func stallReason(default fallback: String) -> String {
        live?.avDevice.isInUseByAnotherApplication == true ? "Camera is in use by another app" : fallback
    }

    /// The first frame of a session, or the first frame after a stall, arrived.
    private func framesResumed(generation: Int) {
        guard let live, live.generation == generation, let device = activeDevice else { return }
        retryPolicy.recovered()
        backoff.framesFlowed()
        emit(.running(device))
    }
}

// Notification handling. Same file, so it shares the private state above; every handler hops onto `queue` first.
extension CaptureSessionController {
    // MARK: Session notifications

    private func sessionObservers(for avSession: AVCaptureSession, generation: Int) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        let runtimeError = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: avSession, queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? any Error
            let message = error?.localizedDescription ?? "Unknown capture error"
            guard let self else { return }
            self.queue.async { self.handleRuntimeError(generation: generation, message: message) }
        }
        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: avSession, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.handleSessionInterrupted(generation: generation) }
        }
        let interruptionEnded = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: avSession, queue: nil
        ) { _ in
            // The session restarts itself; the first frame after this reports `.running` (framesResumed).
            Self.log.info("Capture session interruption ended")
        }
        return [runtimeError, interrupted, interruptionEnded]
    }

    /// Retry once, then report `.failed(.runtimeFailure)`.
    private func handleRuntimeError(generation: Int, message: String) {
        guard let live, live.generation == generation else { return }
        switch retryPolicy.errorOccurred() {
        case .retry:
            Self.log.error("Runtime error, retrying once: \(message)")
            emit(.interrupted("Camera error: \(message)"))
            rebuild(announceStarting: false)
        case .fail:
            fail(.runtimeFailure(message))
        }
    }

    private func handleSessionInterrupted(generation: Int) {
        guard let live, live.generation == generation else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard watchdog.withLock({ $0.markInterrupted(at: now) }) == .stalled else { return }
        beginStallWait()
        emit(.interrupted(stallReason(default: "Camera session was interrupted")))
    }

    // MARK: System notifications

    /// Installed once, from `init`. Every handler ignores its event unless it matters, so the observers stay for the
    /// controller's whole life, including while capture is stopped.
    private func installSystemObservers() {
        guard systemObservers.isEmpty else { return }
        let workspace = environment.workspaceCenter
        let distributed = environment.distributedCenter

        observeSystemEvent(NSWorkspace.willSleepNotification, on: workspace, event: .begin(.systemSleep))
        observeSystemEvent(NSWorkspace.didWakeNotification, on: workspace, event: .end(.systemSleep))
        observeSystemEvent(NSWorkspace.screensDidSleepNotification, on: workspace, event: .begin(.displaysAsleep))
        observeSystemEvent(NSWorkspace.screensDidWakeNotification, on: workspace, event: .end(.displaysAsleep))
        observeSystemEvent(Notification.Name("com.apple.screenIsLocked"), on: distributed, event: .begin(.screenLocked))
        observeSystemEvent(Notification.Name("com.apple.screenIsUnlocked"), on: distributed, event: .end(.screenLocked))
        // Fast user switching: while another user's session is in front, this one must not use the camera.
        observeSystemEvent(
            NSWorkspace.sessionDidResignActiveNotification, on: workspace, event: .begin(.sessionInactive))
        observeSystemEvent(
            NSWorkspace.sessionDidBecomeActiveNotification, on: workspace, event: .end(.sessionInactive))

        observe(AVCaptureDevice.wasDisconnectedNotification, on: environment.deviceCenter) { [weak self] notification in
            guard let id = (notification.object as? AVCaptureDevice)?.uniqueID, let self else { return }
            self.queue.async { self.handleDeviceDisconnected(id: id) }
        }
        observe(AVCaptureDevice.wasConnectedNotification, on: environment.deviceCenter) { [weak self] notification in
            guard let id = (notification.object as? AVCaptureDevice)?.uniqueID, let self else { return }
            self.queue.async { self.handleDeviceConnected(id: id) }
        }
    }

    private func removeSystemObservers() {
        for observer in systemObservers {
            observer.center.removeObserver(observer.token)
        }
        systemObservers.removeAll()
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: nil, using: handler)
        systemObservers.append(ObserverToken(center: center, token: token))
    }

    private func observeSystemEvent(
        _ name: Notification.Name, on center: NotificationCenter, event: SuspendTracker.Event
    ) {
        observe(name, on: center) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.handle(event) }
        }
    }

    /// Records the event whether or not capture is running (D43). The tracker answers `.none` while capture is
    /// stopped, so only a running or waiting capture reacts.
    private func handle(_ event: SuspendTracker.Event) {
        let directive = suspend.apply(event, isMainDisplayAsleep: environment.isMainDisplayAsleep)
        switch directive {
        case .none:
            break
        case .suspend(let reason):
            Self.log.info("Suspending capture: \(String(describing: reason))")
            cancelRetry()
            teardownSession()
            watchdog.withLock { $0.disarm() }
            // The conditions that caused earlier trouble are gone with the session; a resume starts fresh.
            backoff = RetryBackoff()
            emit(.suspended(reason))
        case .reasonChanged(let reason):
            emit(.suspended(reason))
        case .resume:
            Self.log.info("Resuming capture")
            rebuild(announceStarting: true)
        }
    }

    private func handleDeviceDisconnected(id: String) {
        guard configuration != nil, activeDevice?.id == id, awaitingReconnectID == nil else { return }
        Self.log.info("Camera disconnected")
        awaitingReconnectID = id
        // While suspended the session is already down; resuming notices the missing device.
        guard !suspend.isSuspended else { return }
        teardownSession()
        watchdog.withLock { $0.disarm() }
        emit(.interrupted(Self.disconnectedMessage))
        scheduleRetry()
    }

    private func handleDeviceConnected(id: String) {
        guard configuration != nil, awaitingReconnectID == id, !suspend.isSuspended else { return }
        Self.log.info("Camera reconnected")
        rebuild(announceStarting: true)
    }
}
