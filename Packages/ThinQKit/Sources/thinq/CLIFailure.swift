import ThinQKit

/// Everything that ends a CLI run unsuccessfully, with its sysexits-style exit code.
enum CLIFailure: Error, CustomStringConvertible {
    /// Bad arguments; usage is printed after the message.
    case usage(String)
    /// Missing token, unwritable client-id file, …
    case configuration(String)
    case api(ThinQError)
    case model(ACModelError)

    var exitCode: Int32 {
        switch self {
        case .usage: 64        // EX_USAGE
        case .configuration: 78 // EX_CONFIG
        case .api, .model: 1
        }
    }

    var description: String {
        switch self {
        case .usage(let message), .configuration(let message):
            message
        case .api(let error):
            Self.describe(error)
        case .model(let error):
            error.description
        }
    }

    private static func describe(_ error: ThinQError) -> String {
        if error.isTokenInvalid {
            return "\(error)\nThe token was rejected. Create a new one at https://connect-pat.lgthinq.com and update THINQ_PAT."
        }
        if error.isRateLimited {
            return "\(error)\nLG's hourly API quota is exhausted; try again later."
        }
        if error.isDeviceOffline {
            return "\(error)\nThe AC is offline (unplugged or Wi-Fi down)."
        }
        if error.apiCode == .commandNotSupportedInPowerOff {
            // Redundant POWER_OFF is swallowed by `set`, so any 2304 seen here means the AC is off.
            return "\(error)\nThe AC is off; run `thinq set <deviceId> power on` first."
        }
        if error.apiCode == .notSupportedCountry {
            return "\(error)\nTHINQ_COUNTRY must match the ThinQ account's country."
        }
        return error.description
    }
}
