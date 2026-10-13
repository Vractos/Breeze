import Foundation

/// Everything a `ThinQClient` needs to talk to LG. `description`, `debugDescription` and the
/// reflection mirror redact the token so `print(config)` / `dump(config)` can never leak it.
public struct ThinQConfiguration: Sendable {
    /// The personal access token (PAT). Secret.
    public var accessToken: String
    /// ISO 3166-1 alpha-2 country of the ThinQ account, e.g. `"BR"`. Sent as `x-country`.
    public var countryCode: String
    /// Stable per-installation id, sent as `x-client-id` (see `ThinQClientID`).
    public var clientID: String
    /// API region; derived from `countryCode` unless overridden.
    public var region: ThinQRegion
    /// Per-request timeout.
    public var timeout: Duration

    public init(
        accessToken: String,
        countryCode: String,
        clientID: String,
        region: ThinQRegion? = nil,
        timeout: Duration = .seconds(15)
    ) {
        self.accessToken = accessToken
        self.countryCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.clientID = clientID
        self.region = region ?? ThinQRegion.forCountry(countryCode)
        self.timeout = timeout
    }

    /// `timeout` as the `TimeInterval` URLRequest wants.
    var timeoutInterval: TimeInterval {
        timeout / .seconds(1)
    }
}

extension ThinQConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ThinQConfiguration(country: \(countryCode), region: \(region.rawValue), clientID: \(clientID), accessToken: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "accessToken": "<redacted>",
                "countryCode": countryCode,
                "clientID": clientID,
                "region": region,
                "timeout": timeout,
            ],
            displayStyle: .struct
        )
    }
}
