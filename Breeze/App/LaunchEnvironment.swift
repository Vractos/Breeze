import Foundation

/// Facts about how the process was launched.
enum LaunchEnvironment {
    /// True when the app is only hosting the unit-test bundle.
    ///
    /// Gotcha: BreezeTests is hosted in the app, so `BreezeApp.init` runs during `xcodebuild
    /// test`. Without this check the real store would read the Keychain and call LG (spending
    /// quota) on every test run. Xcode sets `XCTestConfigurationFilePath` for hosted XCTest and
    /// Swift Testing runs alike; `XCTestBundlePath` / `XCTestSessionIdentifier` are fallbacks.
    static var isHostingUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }

    /// True when Xcode launched the app only to render SwiftUI previews.
    ///
    /// Gotcha: the preview host runs `BreezeApp` for real, so without this check every
    /// preview session adds a dead snowflake to the menu bar and reads the Keychain.
    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// True for a normal launch: not a test host and not a preview host.
    static var isInteractiveLaunch: Bool {
        !isHostingUnitTests && !isRunningForPreviews
    }
}
