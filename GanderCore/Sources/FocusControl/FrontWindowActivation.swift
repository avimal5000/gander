/// The order of the activation calls (SPEC D53), apart from the calls themselves so the fallback can be tested.
enum FrontWindowActivation {
    enum Outcome: Equatable {
        /// The app came to the front with only its front window.
        case frontWindowOnly
        /// Front-window-only did not bring the app to the front, so the plain activation ran. `status` is what
        /// front-window-only returned: 0 when it was accepted but the app did not come forward in time.
        case fellBack(status: Int32, requested: Bool)
        /// The request was cancelled while waiting, so no second activation was asked for.
        case cancelled
    }

    /// Tries front-window-only activation, like a click on the raised window. If the system refuses it, no longer has
    /// it, or the app does not come to the front, `fallback` activates with no options, which brings the app's main
    /// and key windows but not every window.
    ///
    /// - Parameters:
    ///   - frontWindowOnly: Returns 0 when the request was accepted, else an `OSStatus`.
    ///   - becomesFrontmost: True once the app is frontmost, false after the wait or on cancellation.
    ///   - fallback: Returns whether the system took the request.
    static func run(
        frontWindowOnly: () async -> Int32,
        becomesFrontmost: () async -> Bool,
        fallback: () async -> Bool
    ) async -> Outcome {
        let status = await frontWindowOnly()
        if status == 0, await becomesFrontmost() { return .frontWindowOnly }
        if Task.isCancelled { return .cancelled }
        return .fellBack(status: status, requested: await fallback())
    }
}
