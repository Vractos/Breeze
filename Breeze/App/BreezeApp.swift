import SwiftUI
import ThinQKit

@main
struct BreezeApp: App {
    @State private var settings: AppSettings
    @State private var store: ACStore
    @State private var loginItem: LoginItem

    init() {
        let settings = AppSettings(defaults: .standard)
        let store = ACStore(
            makeClient: { configuration in ThinQClient(configuration: configuration) },
            tokenStore: KeychainTokenStore(),
            settings: settings,
            clock: SystemStoreClock()
        )
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _loginItem = State(initialValue: LoginItem(service: MainAppLoginItemService()))

        // Start at launch, not when the panel first opens: MenuBarExtra builds its window
        // content lazily, so a `.task` on PanelView would leave the menu bar label empty and
        // polling off until the first click. `start()` is idempotent.
        if LaunchEnvironment.isInteractiveLaunch {
            Task { await store.start() }
        }
    }

    var body: some Scene {
        // Test and preview hosts run this scene too; keep them out of the menu bar.
        MenuBarExtra(isInserted: .constant(LaunchEnvironment.isInteractiveLaunch)) {
            PanelView()
                .environment(store)
                .environment(settings)
        } label: {
            StatusLabel(snapshot: store.snapshot, showsTemperature: settings.showTemperatureInMenuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .environment(settings)
                .environment(loginItem)
        }
        .windowResizability(.contentSize)
    }
}
