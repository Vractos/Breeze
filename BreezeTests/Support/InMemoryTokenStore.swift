@testable import Breeze

@MainActor
final class InMemoryTokenStore: TokenStore {
    var storedToken: String?
    var failure: KeychainError?

    init(token: String? = nil) {
        storedToken = token
    }

    func token() throws(KeychainError) -> String? {
        if let failure { throw failure }
        return storedToken
    }

    func setToken(_ token: String) throws(KeychainError) {
        if let failure { throw failure }
        storedToken = token
    }

    func deleteToken() throws(KeychainError) {
        if let failure { throw failure }
        storedToken = nil
    }
}
