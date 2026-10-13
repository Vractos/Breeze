import Foundation
@testable import Breeze
import ThinQKit

/// An `ACStore` wired to fakes: scripted API, in-memory token, throwaway defaults, manual clock.
@MainActor
final class StoreHarness {
    let clock = ManualClock()
    let api: FakeThinQAPI
    let tokenStore: InMemoryTokenStore
    let defaults: UserDefaults
    let settings: AppSettings
    let store: ACStore
    /// Every configuration the store built a client with.
    var configurations: [ThinQConfiguration] { recorder.configurations }
    private let recorder = ConfigurationRecorder()

    private let suiteName: String

    init(
        token: String? = "test-token",
        devices: [DeviceSummary] = [Fixtures.livingRoomAC],
        state: DeviceState? = nil,
        profile: DeviceProfile? = nil,
        configure: (AppSettings) -> Void = { _ in }
    ) throws {
        suiteName = "BreezeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Fixtures.MissingFixture(name: suiteName)
        }
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
        configure(settings)
        tokenStore = InMemoryTokenStore(token: token)
        api = FakeThinQAPI(clock: clock, devices: devices, profile: try profile ?? Fixtures.profile(), state: try state ?? Fixtures.offState())

        let api = self.api
        let recorder = self.recorder
        store = ACStore(
            makeClient: { configuration in
                recorder.configurations.append(configuration)
                return api
            },
            tokenStore: tokenStore,
            settings: settings,
            clock: clock
        )
    }

    /// Stops the store's loops and removes the defaults domain.
    func tearDown() {
        store.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}
