import Foundation
import Security

/// Stores the PAT as a generic-password item (service `com.vinicius.Breeze`, account `thinq-pat`).
///
/// Gotcha: this deliberately does NOT set `kSecUseDataProtectionKeychain`. The app is ad-hoc
/// signed with no team, and the data-protection keychain requires a `keychain-access-groups` /
/// application-identifier entitlement that only a team-signed app can have; without it every
/// call fails with `errSecMissingEntitlement` (-34018). The legacy file-based login keychain works
/// for a sandboxed ad-hoc app. `kSecAttrAccessibleAfterFirstUnlock` is set for when the app moves
/// to the data-protection keychain; the file-based keychain ignores it.
///
/// Gotcha (the price of the above): the file-based keychain records the creating app in the
/// item's access list by its designated requirement, and an ad-hoc signature's requirement is
/// its cdhash, which changes with every build. So after each rebuild or update the first read
/// shows macOS's "Breeze wants to use your confidential information" prompt, synchronously on
/// the main actor (at launch, even at login). "Always Allow" lasts until the next build; "Deny"
/// makes every call fail with `errSecAuthFailed`, reported as `KeychainError.accessDenied`
/// (save and remove fail the same way) until the item is deleted in Keychain Access. The fix is
/// signing, not code: set a development team (Signing & Capabilities in Xcode) so the
/// requirement becomes team-based and stable, then optionally move to the data-protection
/// keychain (`kSecUseDataProtectionKeychain`), which has no access-list prompts at all.
struct KeychainTokenStore: TokenStore {
    /// Changing either value orphans the PAT users already saved.
    private static let service = "com.vinicius.Breeze"
    private static let account = "thinq-pat"

    func token() throws(KeychainError) -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw .invalidData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Updates the existing item, or adds it when there is none.
    func setToken(_ token: String) throws(KeychainError) {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addQuery = itemQuery.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    func deleteToken() throws(KeychainError) {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Identifies the one item; shared by every operation.
    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }
}
