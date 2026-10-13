import Foundation
import ThinQKit

extension ThinQError {
    /// A short localized sentence for `ACStore.Phase.error` / command failures. Never includes
    /// request details (and so never the token).
    var userMessage: String {
        switch self {
        case .transport:
            String(localized: "Can't reach LG ThinQ. Check your internet connection.")
        case .api(let code, _) where code == .notSupportedCountry:
            String(localized: "This ThinQ account isn't registered in the selected country.")
        case .api(let code, _):
            String(localized: "LG ThinQ returned error \(code.rawValue) (\(code.name)).")
        case .decoding, .encoding:
            String(localized: "LG ThinQ sent a response Breeze doesn't understand.")
        case .httpStatus(let status):
            String(localized: "LG ThinQ returned HTTP status \(status).")
        case .invalidArgument:
            String(localized: "The selected device id is invalid.")
        }
    }
}
