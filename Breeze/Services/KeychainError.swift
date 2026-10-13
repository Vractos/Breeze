import Foundation

/// A Keychain (`SecItem*`) failure.
nonisolated enum KeychainError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The item exists but this build may not use it: the user denied the access prompt, or no
    /// prompt could be shown (`errSecAuthFailed`, `errSecUserCanceled`,
    /// `errSecInteractionNotAllowed`). See `KeychainTokenStore` for why ad-hoc builds hit this.
    case accessDenied(OSStatus)
    /// `SecItem*` returned a status other than success / item-not-found.
    case unexpectedStatus(OSStatus)
    /// The item exists but its data is not a UTF-8 string.
    case invalidData

    /// Maps a failing `SecItem*` status to `.accessDenied` or `.unexpectedStatus`.
    init(status: OSStatus) {
        switch status {
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            self = .accessDenied(status)
        default:
            self = .unexpectedStatus(status)
        }
    }

    var description: String {
        switch self {
        case .accessDenied(let status):
            return "Keychain access denied (\(status)): \(Self.message(for: status))"
        case .unexpectedStatus(let status):
            return "Keychain error \(status): \(Self.message(for: status))"
        case .invalidData:
            return "Keychain item is not a UTF-8 string"
        }
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "unknown"
    }
}
