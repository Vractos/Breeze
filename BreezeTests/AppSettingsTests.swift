import Foundation
import Testing
@testable import Breeze

@Suite("AppSettings")
@MainActor
struct AppSettingsTests {
    private let suiteName = "BreezeTests.AppSettings.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func defaults() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.countryCode == "BR")
        #expect(settings.selectedDeviceID == nil)
        #expect(settings.pollIntervalSeconds == 120)
        #expect(settings.pollInterval == .seconds(120))
        #expect(settings.showTemperatureInMenuBar)
        #expect(UUID(uuidString: settings.clientID) != nil)
        #expect(settings.clientID == settings.clientID.lowercased())
    }

    @Test func clientIDIsGeneratedOnceAndPersisted() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppSettings(defaults: defaults).clientID
        let second = AppSettings(defaults: defaults).clientID

        #expect(first == second)
    }

    @Test func changesPersist() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.countryCode = "US"
        settings.selectedDeviceID = "ac-1"
        settings.pollIntervalSeconds = 300
        settings.showTemperatureInMenuBar = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.countryCode == "US")
        #expect(reloaded.selectedDeviceID == "ac-1")
        #expect(reloaded.pollIntervalSeconds == 300)
        #expect(!reloaded.showTemperatureInMenuBar)

        settings.selectedDeviceID = nil
        #expect(AppSettings(defaults: defaults).selectedDeviceID == nil)
    }

    @Test(arguments: [(10, 60), (60, 60), (121, 121), (600, 600), (601, 600)])
    func pollIntervalIsClamped(configured: Int, expected: Int) throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.pollIntervalSeconds = configured

        #expect(settings.pollInterval == .seconds(expected))
    }
}
