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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countryCode = defaults.string(forKey: Self.countryCodeKey) ?? Self.defaultCountryCode
        clientID = Self.loadOrCreateClientID(in: defaults)
        selectedDeviceID = defaults.string(forKey: Self.selectedDeviceIDKey)
        pollIntervalSeconds = defaults.object(forKey: Self.pollIntervalSecondsKey) as? Int ?? Self.defaultPollIntervalSeconds
        showTemperatureInMenuBar = defaults.object(forKey: Self.showTemperatureInMenuBarKey) as? Bool ?? true
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
