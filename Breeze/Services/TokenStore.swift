/// Where the ThinQ personal access token (PAT) lives. The app uses `KeychainTokenStore`; tests
/// use an in-memory double. Implementations must never log the token.
@MainActor
protocol TokenStore {
    /// The saved token, or `nil` when none has been saved yet.
    func token() throws(KeychainError) -> String?
    func setToken(_ token: String) throws(KeychainError)
    /// Succeeds when there is nothing to delete.
    func deleteToken() throws(KeychainError)
}
