import Testing

@testable import CameraService

@Suite("Runtime error retry policy")
struct RuntimeRetryPolicyTests {
    @Test func firstErrorRetriesAndSecondFails() {
        var policy = RuntimeRetryPolicy()
        #expect(policy.errorOccurred() == .retry)
        #expect(policy.errorOccurred() == .fail)
        #expect(policy.errorOccurred() == .fail)
    }

    @Test func recoveryRestoresTheBudget() {
        var policy = RuntimeRetryPolicy()
        #expect(policy.errorOccurred() == .retry)
        policy.recovered()
        #expect(policy.errorOccurred() == .retry)
        #expect(policy.errorOccurred() == .fail)
    }

    @Test func resetStartsAFreshRun() {
        var policy = RuntimeRetryPolicy()
        _ = policy.errorOccurred()
        _ = policy.errorOccurred()
        policy.reset()
        #expect(policy.retriesUsed == 0)
        #expect(policy.errorOccurred() == .retry)
    }

    @Test func zeroRetriesFailsImmediately() {
        var policy = RuntimeRetryPolicy(maxRetries: 0)
        #expect(policy.errorOccurred() == .fail)
    }
}
