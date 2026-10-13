#if DEBUG
/// A token store for previews; never touches the Keychain.
final class PreviewTokenStore: TokenStore {
    private var storedToken: String?

    init(token: String?) {
        storedToken = token
    }

    func token() throws(KeychainError) -> String? { storedToken }
    func setToken(_ token: String) throws(KeychainError) { storedToken = token }
    func deleteToken() throws(KeychainError) { storedToken = nil }
}
#endif
