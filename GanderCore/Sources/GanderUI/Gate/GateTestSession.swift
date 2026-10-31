import Foundation
import GanderModels

/// A monotonic clock in seconds. Injected so phase timing is testable without sleeping.
typealias GateClock = @Sendable () -> TimeInterval

/// The pure state machine behind the guided gate test (CONTRACT 6.5, SPEC F7).
///
/// Steps are rounds x displays, round-major, displays in layout order (left to right). Each step has a **settle**
/// phase (samples discarded) followed by a **hold** phase (every sample recorded, including frames without a
/// face). Time comes only from the injected `clock`: a phase starts at the moment the machine first observes the
/// previous phase's end, so the schedule is driven by whichever of `advance()` or `ingest(_:)` runs first and a
/// sample that arrives after the hold deadline is never recorded into the finished segment.
///
/// The type performs no I/O and owns no timers; `AppModel` calls `advance()` from a timer and `ingest(_:)` from
/// the sample stream.
struct GateTestSession {
    /// Fewer displays than this cannot be separated.
    static let minimumDisplays = 2

    enum Phase: Equatable, Sendable {
        case pending
        case settling
        case holding
        case finished
        case cancelled
    }

    /// One display visit.
    struct Step: Equatable, Sendable {
        /// 1-based index across the whole test.
        let number: Int
        /// 1-based round.
        let round: Int
        /// 1-based position of the display in layout order.
        let displayNumber: Int
        let display: DisplayInfo
    }

    let layout: DisplayLayout
    let cameraName: String?
    let configuration: GateTestConfiguration
    let steps: [Step]

    private let clock: GateClock
    private let settleDuration: TimeInterval
    private(set) var phase: Phase = .pending
    private(set) var stepIndex = 0
    private var phaseStart: TimeInterval = 0
    private var segments: [TraceSegment] = []
    private var currentSamples: [PoseSample] = []

    init(
        layout: DisplayLayout,
        cameraName: String?,
        configuration: GateTestConfiguration,
        settleDuration: TimeInterval = GateTestConfiguration.settleDuration,
        clock: @escaping GateClock
    ) {
        let configuration = configuration.clamped
        self.layout = layout
        self.cameraName = cameraName
        self.configuration = configuration
        self.settleDuration = settleDuration
        self.clock = clock
        var steps: [Step] = []
        for round in 1...configuration.rounds {
            for (offset, display) in layout.displays.enumerated() {
                steps.append(Step(number: steps.count + 1, round: round, displayNumber: offset + 1, display: display))
            }
        }
        self.steps = steps
    }

    /// True while the test is waiting for samples (settling or holding).
    var isActive: Bool { phase == .settling || phase == .holding }

    /// The step in progress; `nil` before the start and after the end.
    var currentStep: Step? { isActive ? steps[stepIndex] : nil }

    /// Begins the first step's settle phase. A layout without displays finishes immediately with no segments.
    mutating func start() {
        guard phase == .pending else { return }
        guard !steps.isEmpty else {
            phase = .finished
            return
        }
        stepIndex = 0
        phase = .settling
        phaseStart = clock()
    }

    /// Applies any phase transitions that are due at the current clock reading.
    mutating func advance() {
        guard isActive else { return }
        let now = clock()
        if phase == .settling, now - phaseStart >= settleDuration {
            phase = .holding
            phaseStart = now
            currentSamples = []
        }
        if phase == .holding, now - phaseStart >= configuration.holdDuration {
            closeCurrentStep(at: now)
        }
    }

    /// Offers a sample that has just arrived. It is recorded only if the hold phase is open at the current clock
    /// reading.
    mutating func ingest(_ sample: PoseSample) {
        advance()
        guard phase == .holding else { return }
        currentSamples.append(sample)
    }

    /// Aborts the test and discards everything recorded so far.
    mutating func cancel() {
        guard phase != .finished else { return }
        phase = .cancelled
        segments = []
        currentSamples = []
    }

    /// A snapshot of the current phase for the UI; `nil` unless settling or holding.
    var progress: GateProgress? {
        guard let step = currentStep else { return nil }
        let duration = phase == .settling ? settleDuration : configuration.holdDuration
        let elapsed = min(max(0, clock() - phaseStart), duration)
        return GateProgress(
            phase: phase == .settling ? .settle : .hold,
            stepNumber: step.number,
            stepCount: steps.count,
            round: step.round,
            rounds: configuration.rounds,
            displayNumber: step.displayNumber,
            displayCount: layout.displays.count,
            display: step.display,
            phaseElapsed: elapsed,
            phaseDuration: duration,
            recordedSamples: phase == .holding ? currentSamples.count : 0,
            recordedFaces: phase == .holding ? currentSamples.filter { $0.pose != nil }.count : 0
        )
    }

    /// The finished test as a labeled trace; `nil` unless the session ran to completion.
    func makeTrace(id: UUID = UUID(), createdAt: Date = Date()) -> PoseTrace? {
        guard phase == .finished else { return nil }
        return PoseTrace(id: id, createdAt: createdAt, cameraName: cameraName, layout: layout, segments: segments)
    }

    private mutating func closeCurrentStep(at now: TimeInterval) {
        let step = steps[stepIndex]
        segments.append(TraceSegment(displayID: step.display.id, round: step.round, samples: currentSamples))
        currentSamples = []
        if stepIndex + 1 < steps.count {
            stepIndex += 1
            phase = .settling
            phaseStart = now
        } else {
            phase = .finished
        }
    }
}
