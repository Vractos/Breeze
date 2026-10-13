import Foundation
import Observation
import ThinQKit

/// The app's small persistent preferences, backed by `UserDefaults` (an injectable suite, so
/// tests use a throwaway domain). The PAT is not here; it lives in the Keychain (`TokenStore`).
@Observable
@MainActor
final class AppSettings {
    static let defaultCountryCode = "BR"
    static let defaultPollIntervalSeconds = 120
    /// The poll interval the store actually uses is clamped to this range.
    static let pollIntervalRange = 60...600

    private static let countryCodeKey = "countryCode"
    private static let clientIDKey = "clientID"
    private static let selectedDeviceIDKey = "selectedDeviceID"
    private static let pollIntervalSecondsKey = "pollIntervalSeconds"
    private static let showTemperatureInMenuBarKey = "showTemperatureInMenuBar"
    private static let deviceNicknamesKey = "deviceNicknames"
    private static let energyPricePerKWhKey = "energyPricePerKWh"
    /// Prices are stored as locale-independent text ("0.85"), so a locale change never misreads
    /// them and `Decimal` keeps its exact value.
    private static let priceStorageLocale = Locale(identifier: "en_US_POSIX")

    @ObservationIgnored private let defaults: UserDefaults

    /// ISO 3166-1 alpha-2 country of the ThinQ account (sent as `x-country`).
    var countryCode: String {
        didSet { defaults.set(countryCode, forKey: Self.countryCodeKey) }
    }

    /// Stable `x-client-id`, generated once on first launch. LG throttles accounts that keep
    /// registering new client ids, so this is never regenerated.
    let clientID: String

    /// The device the user picked; `nil` until the store auto-selects the first AC.
    var selectedDeviceID: String? {
        didSet { defaults.set(selectedDeviceID, forKey: Self.selectedDeviceIDKey) }
    }

    /// As entered by the user; read `pollInterval` for the clamped value.
    var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Self.pollIntervalSecondsKey) }
    }

    var showTemperatureInMenuBar: Bool {
        didSet { defaults.set(showTemperatureInMenuBar, forKey: Self.showTemperatureInMenuBarKey) }
    }

    /// Local names by device id, stored as typed; `DeviceLabel` trims
    /// them and ignores blank ones. Never sent to LG. Change through `setNickname(_:for:)`.
    private(set) var deviceNicknames: [String: String] {
        didSet { defaults.set(deviceNicknames, forKey: Self.deviceNicknamesKey) }
    }

    /// Settings › Energy's optional price per kWh in the locale's currency;
    /// `nil` (the default) shows energy only. Never negative: change it through
    /// `setEnergyPricePerKWh(_:)`.
    private(set) var energyPricePerKWh: Decimal? {
        didSet {
            if let energyPricePerKWh {
                defaults.set(energyPricePerKWh.description, forKey: Self.energyPricePerKWhKey)
            } else {
                defaults.removeObject(forKey: Self.energyPricePerKWhKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countryCode = defaults.string(forKey: Self.countryCodeKey) ?? Self.defaultCountryCode
        clientID = Self.loadOrCreateClientID(in: defaults)
        selectedDeviceID = defaults.string(forKey: Self.selectedDeviceIDKey)
        pollIntervalSeconds = defaults.object(forKey: Self.pollIntervalSecondsKey) as? Int ?? Self.defaultPollIntervalSeconds
        showTemperatureInMenuBar = defaults.object(forKey: Self.showTemperatureInMenuBarKey) as? Bool ?? true
        deviceNicknames = defaults.dictionary(forKey: Self.deviceNicknamesKey) as? [String: String] ?? [:]
        energyPricePerKWh = defaults.string(forKey: Self.energyPricePerKWhKey)
            .flatMap { Decimal(string: $0, locale: Self.priceStorageLocale) }
            .flatMap { Self.isValidPrice($0) ? $0 : nil }
    }

    /// Sets the price, or clears it with `nil`. A negative (or NaN) price is rejected: the stored
    /// price stays as it was and this returns `false`.
    @discardableResult
    func setEnergyPricePerKWh(_ price: Decimal?) -> Bool {
        if let price, !Self.isValidPrice(price) { return false }
        energyPricePerKWh = price
        return true
    }

    private static func isValidPrice(_ price: Decimal) -> Bool {
        !price.isNaN && price >= 0
    }

    /// The nickname as typed, or "" when there is none.
    func nickname(for deviceID: String) -> String {
        deviceNicknames[deviceID] ?? ""
    }

    /// Stores `nickname` untrimmed: Settings writes on every keystroke, and trimming here would
    /// eat the space in "Beach house" while it is being typed. A blank nickname removes the entry.
    func setNickname(_ nickname: String, for deviceID: String) {
        if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deviceNicknames[deviceID] = nil
        } else {
            deviceNicknames[deviceID] = nickname
        }
    }

    /// `pollIntervalSeconds` clamped to `pollIntervalRange`.
    var pollInterval: Duration {
        let clamped = min(max(pollIntervalSeconds, Self.pollIntervalRange.lowerBound), Self.pollIntervalRange.upperBound)
        return .seconds(clamped)
    }

    private static func loadOrCreateClientID(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: clientIDKey), !existing.isEmpty {
            return existing
        }
        let generated = ThinQClientID.generate()
        defaults.set(generated, forKey: clientIDKey)
        return generated
    }
}
