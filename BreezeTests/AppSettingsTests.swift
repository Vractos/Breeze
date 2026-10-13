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
        #expect(settings.deviceNicknames.isEmpty)
        #expect(settings.nickname(for: "ac-1") == "")
        #expect(settings.energyPricePerKWh == nil)
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

    @Test func nicknamesPersistPerDeviceAsTyped() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setNickname("Beach ", for: "ac-1")
        settings.setNickname("Bedroom", for: "ac-2")
        // Kept as typed (trailing space included) so typing "Beach house" isn't cut short;
        // `DeviceLabel` trims when it names the device.
        #expect(settings.nickname(for: "ac-1") == "Beach ")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.deviceNicknames == ["ac-1": "Beach ", "ac-2": "Bedroom"])
        #expect(reloaded.nickname(for: "ac-2") == "Bedroom")
        #expect(reloaded.nickname(for: "ac-3") == "")
    }

    @Test(arguments: ["", "   ", "\n"])
    func aBlankNicknameRemovesTheEntry(blank: String) throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.setNickname("Bedroom", for: "ac-1")
        settings.setNickname("Beach house", for: "ac-2")

        settings.setNickname(blank, for: "ac-1")

        #expect(settings.deviceNicknames == ["ac-2": "Beach house"])
        #expect(AppSettings(defaults: defaults).deviceNicknames == ["ac-2": "Beach house"])
    }

    @Test func energyPricePersistsExactlyAndClears() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let price = try #require(Decimal(string: "0.8547", locale: Locale(identifier: "en_US_POSIX")))

        #expect(settings.setEnergyPricePerKWh(price))
        #expect(AppSettings(defaults: defaults).energyPricePerKWh == price)

        #expect(settings.setEnergyPricePerKWh(0))
        #expect(AppSettings(defaults: defaults).energyPricePerKWh == 0)

        #expect(settings.setEnergyPricePerKWh(nil))
        #expect(settings.energyPricePerKWh == nil)
        #expect(AppSettings(defaults: defaults).energyPricePerKWh == nil)
    }

    @Test func aNegativeEnergyPriceIsRejected() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.setEnergyPricePerKWh(1)

        #expect(!settings.setEnergyPricePerKWh(-0.5))
        #expect(!settings.setEnergyPricePerKWh(.nan))

        #expect(settings.energyPricePerKWh == 1)
        #expect(AppSettings(defaults: defaults).energyPricePerKWh == 1)
    }

    @Test(arguments: ["-1", "abc", ""])
    func anInvalidStoredEnergyPriceLoadsAsNone(stored: String) throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(stored, forKey: "energyPricePerKWh")

        #expect(AppSettings(defaults: defaults).energyPricePerKWh == nil)
    }

    @Test func aStoredEnergyPriceIsReadTheSameInAnyLocale() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Written as "0.85" whatever the locale; a pt_BR reading must not turn it into 85.
        defaults.set("0.85", forKey: "energyPricePerKWh")

        let price = try #require(AppSettings(defaults: defaults).energyPricePerKWh)
        #expect(price == (try #require(Decimal(string: "0.85", locale: Locale(identifier: "en_US_POSIX")))))
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
