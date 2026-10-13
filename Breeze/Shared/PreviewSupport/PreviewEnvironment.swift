#if DEBUG
import Foundation
import SwiftUI

/// Builds the store, settings and login item a preview needs, with no Keychain, network or
/// login-item side effects (preferences go to a separate defaults suite).
@MainActor
struct PreviewEnvironment {
    let settings: AppSettings
    let store: ACStore
    let loginItem: LoginItem

    init(scenario: PreviewScenario) {
        let defaults = UserDefaults(suiteName: "com.vinicius.Breeze.previews") ?? .standard
        let settings = AppSettings(defaults: defaults)
        let api = PreviewThinQAPI(stateResults: scenario.stateResults)
        self.settings = settings
        self.store = ACStore(
            makeClient: { _ in api },
            tokenStore: PreviewTokenStore(token: scenario.token),
            settings: settings,
            clock: SystemStoreClock()
        )
        self.loginItem = LoginItem(
            service: PreviewLoginItemService(),
            defaults: defaults,
            appURL: Bundle.main.bundleURL
        )
    }
}
#endif
