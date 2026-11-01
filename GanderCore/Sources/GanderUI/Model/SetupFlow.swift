/// The pure state machine behind the Set Up Gander window (SPEC F20, CONTRACT 6.5.3): which step shows, decided by a
/// few facts and by the user's moves. It performs no I/O; `AppModel+Setup` feeds it the facts and acts on its steps.
///
/// On first setup (nothing calibrated yet) the window opens on a `welcome` step, a paged intro of `introPageCount` pages
/// (Next, Back, Skip intro); leaving it, from the last page or by skipping, moves on to the first step below that
/// applies. The welcome step is not one of the five numbered steps.
///
/// Steps run in this order, and the window opens at the first one that applies:
/// 1. `cameraAccess`, unless the camera is authorized;
/// 2. `accessibility`, unless Accessibility is trusted or the user skipped it;
/// 3. `cameraCheck`;
/// 4. `calibrating`;
/// 5. `result`.
struct SetupFlow: Equatable, Sendable {
    enum Step: Int, Equatable, Sendable {
        /// First setup only: what Gander does and its privacy promise (SPEC F26). Not counted in "Step N of 5".
        case welcome = 0
        case cameraAccess = 1
        case accessibility
        case cameraCheck
        case calibrating
        case result
    }

    /// Everything the permission steps depend on.
    struct Facts: Equatable, Sendable {
        var cameraAuthorized: Bool
        var accessibilityTrusted: Bool
        /// The user chose "Skip for now" during this app run.
        var accessibilitySkipped: Bool
    }

    /// Number of steps, for "Step 3 of 5".
    static let stepCount = 5

    /// Pages in the welcome intro: what Gander does, how it works, the privacy promise, and where to find it.
    static let introPageCount = 4

    private(set) var step: Step
    /// The intro page showing while `step` is `.welcome`, from 0 to `introPageCount - 1`.
    private(set) var introPage = 0

    /// Opens at the first step that applies to `facts`, or on the welcome step when `showsWelcome` is set (first
    /// setup, with an empty calibration library).
    init(facts: Facts, showsWelcome: Bool = false) {
        step = showsWelcome ? .welcome : Self.firstStep(for: facts)
    }

    /// The first step that applies: camera access unless authorized; Accessibility unless trusted or skipped;
    /// otherwise the camera check.
    static func firstStep(for facts: Facts) -> Step {
        if !facts.cameraAuthorized { return .cameraAccess }
        if !facts.accessibilityTrusted && !facts.accessibilitySkipped { return .accessibility }
        return .cameraCheck
    }

    /// True while the window waits for a permission.
    var isPermissionStep: Bool { step == .cameraAccess || step == .accessibility }

    /// True while the camera must run for the window: the camera check and the calibration itself.
    var needsCamera: Bool { step == .cameraCheck || step == .calibrating }

    /// True while automatic switching holds so the user can move and look freely: the camera check and the calibration.
    /// The result step doesn't hold: while the window is in front, "Gander in front" already does, and a window left
    /// behind other apps must not stop switching unseen.
    var holdsTracking: Bool { step == .cameraCheck || step == .calibrating }

    // MARK: Moves

    /// Applies new facts. A granted permission moves the window on; a revoked camera permission moves it back to
    /// the camera step from any step before the calibration. Later steps never move on their own, and neither does
    /// the welcome step: only **Get Started** leaves it.
    mutating func update(_ facts: Facts) {
        switch step {
        case .welcome:
            break
        case .cameraAccess:
            if facts.cameraAuthorized { step = Self.firstStep(for: facts) }
        case .accessibility:
            if !facts.cameraAuthorized {
                step = .cameraAccess
            } else if facts.accessibilityTrusted || facts.accessibilitySkipped {
                step = .cameraCheck
            }
        case .cameraCheck:
            if !facts.cameraAuthorized { step = .cameraAccess }
        case .calibrating, .result:
            break
        }
    }

    /// True on the last intro page, where the primary button starts the setup instead of turning the page.
    var isLastIntroPage: Bool { introPage == Self.introPageCount - 1 }

    /// "Next" on the intro: the following page. Stays on the last page; its button leaves the intro instead.
    mutating func nextIntroPage() {
        if step == .welcome, !isLastIntroPage { introPage += 1 }
    }

    /// "Back" on the intro: the page before. Stays on the first page.
    mutating func previousIntroPage() {
        if step == .welcome, introPage > 0 { introPage -= 1 }
    }

    /// "Set Up Gander" on the last intro page, or "Skip intro" on any page: on to the first step that applies to `facts`.
    mutating func getStarted(_ facts: Facts) {
        if step == .welcome { step = Self.firstStep(for: facts) }
    }

    /// "Start calibration" on the camera check.
    mutating func startCalibration() {
        if step == .cameraCheck { step = .calibrating }
    }

    /// The calibration ran to the end (its fit succeeded or failed; the result step says which).
    mutating func calibrationFinished() {
        if step == .calibrating { step = .result }
    }

    /// Cancel, Esc, or an interrupted run: back to the camera check.
    mutating func calibrationCancelled() {
        if step == .calibrating { step = .cameraCheck }
    }

    /// "Calibrate again" on the result.
    mutating func calibrateAgain() {
        if step == .result { step = .cameraCheck }
    }
}
