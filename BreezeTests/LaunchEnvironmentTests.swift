import Testing
@testable import Breeze

@Suite("LaunchEnvironment")
struct LaunchEnvironmentTests {
    /// Guards the check that keeps the hosted test run from starting the real store.
    @Test @MainActor func detectsTheTestHost() {
        #expect(LaunchEnvironment.isHostingUnitTests)
    }
}
